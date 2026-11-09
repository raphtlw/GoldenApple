import Foundation

/// Prepares an instance and runs the game, in this order: check components, choose Java, install files,
/// extract natives, copy plain assets, build the command, run the game, delete `Natives/`.
nonisolated struct LaunchPipeline: Sendable {
    struct Request: Sendable {
        let instance: Instance
        let session: LaunchSession
        let metadataMode: MetadataMode
        let join: JoinTarget?
    }

    /// Progress units of each step.
    private enum Weight {
        static let components = 2
        static let java = 10
        static let libraries = 25
        static let assets = 55
        static let natives = 4
        static let plainAssets = 3
        static let start = 1
    }

    static let totalProgressCount = Weight.components + Weight.java + Weight.libraries + Weight.assets + Weight.natives + Weight.plainAssets + Weight.start

    let services: LauncherServices

    /// Returns the exit code when the game exits with 0 or after a stop. Any other exit is a `gameCrashed` error,
    /// or a `forgeInstallerFailed` error when it happened in the Forge or NeoForge installer phase.
    /// Every log line of the launch goes to `Latest Launch.log`.
    @concurrent
    func run(_ request: Request, game: RunningGame, log: LaunchLog, progress: ProgressManager) async throws -> Int32 {
        let instance = try services.instances.current(request.instance)
        let mode = request.metadataMode
        var log = log
        log.file = log.openFile(instance.paths.logFile(.latestLaunch))
        defer { log.file?.close() }

        log.status("Checking the versions of \(instance.name)")
        let components = try services.instances.components(of: instance)
        _ = try await services.resolver.resolve(components, mode: .check, metadataMode: mode)
        let profile = try await services.resolver.profile(for: components, metadataMode: mode)
        guard let mainClass = profile.mainClass.nonEmpty else {
            throw LauncherError.missingMainClass(instance.name)
        }
        progress.complete(count: Weight.components)

        log.status("Choosing Java")
        let java = try await services.javaSelector.selectJava(
            for: profile,
            instance: instance,
            mode: mode,
            subprogress: progress.subprogress(assigningCount: Weight.java)
        )
        log.launcher("Using Java \(java.version) from \(java.vendor) at \(java.path.path)")

        let assetIndex = try await installGameFiles(for: profile, mode: mode, log: log, progress: progress)

        log.status("Extracting native libraries")
        let natives = instance.paths.natives
        defer { removeNatives(natives, log: log) }
        try await NativesExtractor(libraries: services.libraries, stagingFolder: services.paths.downloads)
            .extract(profile.nativeLibraries, into: natives)
        progress.complete(count: Weight.natives)

        var gameAssetsFolder = services.paths.assets
        if let assetIndex {
            log.status("Copying assets")
            try await services.assets.copyPlainFiles(assetIndex.index, id: assetIndex.reference.id, gameFolder: instance.gameFolder)
            gameAssetsFolder = services.assets.gameAssetsFolder(assetIndex.index, id: assetIndex.reference.id, gameFolder: instance.gameFolder)
        }
        progress.complete(count: Weight.plainAssets)

        let command = LaunchCommandBuilder(paths: services.paths, configuration: services.configuration, libraries: services.libraries).command(for: LaunchCommandInput(
            instance: instance,
            profile: profile,
            mainClass: mainClass,
            java: java,
            session: request.session,
            join: await resolvedJoin(request.join, log: log),
            assetIndexName: assetIndex?.reference.id ?? "",
            gameAssetsFolder: gameAssetsFolder,
            settings: services.settings.current,
            instanceEnvironment: try services.instances.configuration(of: instance).environment
        ))
        try FileSystem.createFolder(command.workingDirectory)
        log.launcher("Command: \(command.displayText)")
        try Task.checkCancellation()

        log.status("Starting the game")
        let installer = mainClass == LaunchCommandBuilder.forgeWrapperMainClass ? installerMonitor(for: instance, log: log) : nil
        return try await play(command, instance: instance, installer: installer, game: game, log: log, progress: progress)
    }

    // MARK: Steps

    private struct LoadedAssetIndex {
        let reference: AssetIndexReference
        let index: AssetIndex
    }

    /// Online, downloads libraries, natives, Maven files, agents, the game jar, the asset index and objects.
    /// Offline, fails when any of them is missing.
    private func installGameFiles(for profile: LaunchProfile, mode: MetadataMode, log: LaunchLog, progress: ProgressManager) async throws -> LoadedAssetIndex? {
        let libraryItems = services.libraries.downloadItems(for: profile)
        switch mode {
        case .online:
            log.status("Downloading libraries")
            try await services.downloads.download(libraryItems, subprogress: progress.subprogress(assigningCount: Weight.libraries))
            guard let reference = profile.assetIndex else {
                progress.complete(count: Weight.assets)
                return nil
            }
            log.status("Downloading assets")
            let index = try await services.assets.downloadIndex(reference)
            try await services.assets.downloadObjects(index, subprogress: progress.subprogress(assigningCount: Weight.assets))
            return LoadedAssetIndex(reference: reference, index: index)
        case .offline:
            log.status("Checking game files")
            let index = try profile.assetIndex.map { LoadedAssetIndex(reference: $0, index: try services.assets.loadIndex($0)) }
            let objectItems = index.map { services.assets.objectDownloadItems($0.index) } ?? []
            let missing = (libraryItems + objectItems).filter { !FileSystem.exists($0.destination) }
            guard missing.isEmpty else {
                throw LauncherError.filesMissingOffline(missing.map(\.destination.path))
            }
            progress.complete(count: Weight.libraries + Weight.assets)
            return index
        }
    }

    private func resolvedJoin(_ join: JoinTarget?, log: LaunchLog) async -> JoinTarget? {
        guard case .server(let host, let port) = join else {
            return join
        }
        let requested = ServerAddress(host: host, port: port)
        let resolved = await ServerAddressResolver.resolve(requested)
        if resolved != requested {
            log.launcher("Server \(host):\(port) uses \(resolved.host):\(resolved.port) from its SRV record")
        }
        return .server(host: resolved.host, port: resolved.port)
    }

    /// ForgeWrapper runs the Forge or NeoForge installer inside the game process, so its output is watched.
    private func installerMonitor(for instance: Instance, log: LaunchLog) -> ForgeInstallerMonitor {
        let logFileURL = instance.paths.logFile(.forgeInstaller)
        return ForgeInstallerMonitor(
            loaderName: instance.loader?.displayName ?? ModLoader.forge.displayName,
            logFileURL: logFileURL,
            logFile: log.openFile(logFileURL)
        )
    }

    private func play(
        _ command: LaunchCommand,
        instance: Instance,
        installer: ForgeInstallerMonitor?,
        game: RunningGame,
        log: LaunchLog,
        progress: ProgressManager
    ) async throws -> Int32 {
        let process = GameProcess(command)
        game.attach(process)
        let installerWatch = installer.map { installer in
            Task { await installer.watch(process, log: log) }
        }
        defer { installerWatch?.cancel() }
        let exit = try await process.run(
            onStart: { processID in
                installer?.begin()
                progress.complete(count: Weight.start)
                recordLastPlayed(instance, log: log)
                log.launcher("Game started with process ID \(processID)")
                log.send(.gameStarted(processID: processID))
            },
            onLine: { line, isStandardError in
                log.game(line, isStandardError: isStandardError, installer: installer)
            }
        )
        log.send(.gameExited(code: exit.code))
        if let installer, let failure = installer.failure(after: exit) {
            log.launcher("The \(installer.loaderName) installer failed. Its log is in \(installer.logFileURL.path)", level: .error)
            throw LauncherError.forgeInstallerFailed(
                loader: installer.loaderName,
                loaderVersion: instance.loaderVersion ?? "",
                minecraftVersion: instance.minecraftVersion,
                cause: failure.cause,
                stackTrace: failure.stackTrace,
                logFile: installer.logFileURL.path
            )
        }
        if exit.wasStopped {
            log.launcher("Game stopped with exit code \(exit.code)")
            return exit.code
        }
        guard exit.code == 0 else {
            log.launcher("Game crashed with exit code \(exit.code)", level: .error)
            throw LauncherError.gameCrashed(exitCode: exit.code)
        }
        log.launcher("Game exited normally")
        return 0
    }

    private func recordLastPlayed(_ instance: Instance, log: LaunchLog) {
        do {
            try services.instances.updateConfiguration(of: instance) { $0.lastPlayed = Date() }
        } catch {
            log.launcher("Could not save the last played date: \(error.localizedDescription)", level: .warning)
        }
    }

    private func removeNatives(_ folder: URL, log: LaunchLog) {
        do {
            try FileSystem.removeIfPresent(folder)
        } catch {
            log.launcher("Could not delete \(folder.path): \(error.localizedDescription)", level: .warning)
        }
    }
}
