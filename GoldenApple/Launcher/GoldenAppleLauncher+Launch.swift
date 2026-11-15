import Foundation

extension GoldenAppleLauncher {
    /// Prepares the instance, runs the game and returns its exit code after it exits.
    /// Exit code 0 and an exit after `stop(_:)` return the code. Any other exit is a `gameCrashed` error.
    /// Cancelling the calling task stops the launch or the game.
    func launch(
        _ instance: Instance,
        account: Account?,
        mode: LaunchMode,
        join: JoinTarget?,
        events: @escaping @Sendable (LaunchEvent) -> Void,
        subprogress: consuming Subprogress?
    ) async throws -> Int32 {
        let accounts = services.accounts
        return try await launch(
            instance,
            metadataMode: mode.metadataMode,
            join: join,
            events: events,
            progress: ProgressManager.start(subprogress, totalCount: LaunchPipeline.totalProgressCount)
        ) {
            try await accounts.launchSession(for: account, mode: mode) { events(.status($0)) }
        }
    }

    /// Downloads what the instance needs to start, so the first launch does not wait for downloads.
    /// Checks the versions, picks or downloads Java, and downloads libraries and assets. Does not start the game.
    /// `status` receives a short text for each phase.
    func downloadGameFiles(
        for instance: Instance,
        status: @escaping @Sendable (String) -> Void,
        subprogress: consuming Subprogress? = nil
    ) async throws {
        guard services.runningGames.game(for: instance.id) == nil else {
            throw LauncherError.instanceAlreadyRunning(instance.name)
        }
        let progress = ProgressManager.start(subprogress, totalCount: LaunchPipeline.downloadProgressCount)
        let log = LaunchLog(censor: .forLaunchSecrets()) { event in
            if case .status(let text) = event {
                status(text)
            }
        }
        try await LaunchPipeline(services: services).downloadFiles(for: instance, log: log, progress: progress)
    }

    /// Stops the launch or the running game of the instance and waits until it has ended.
    func stop(_ instance: Instance) async {
        guard let game = services.runningGames.game(for: instance.id) else {
            return
        }
        game.stop()
        await game.waitUntilFinished()
    }

    /// True from the start of `launch` until the game has exited.
    func isRunning(_ instance: Instance) -> Bool {
        services.runningGames.game(for: instance.id) != nil
    }

    /// The text of a log file of the instance's last launch, or nil when that file does not exist.
    func launchLog(of instance: Instance, kind: LaunchLogKind) throws -> String? {
        let file = paths.instance(instance.id).logFile(kind)
        guard FileSystem.exists(file) else {
            return nil
        }
        do {
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw LauncherError.unreadableFile(path: file.path, reason: error.localizedDescription)
        }
    }

    /// A plain-text report of an error from `launch`, `createInstance`, `install`, `installModpack`
    /// or `importModpack`, for the player to copy into a bug report.
    nonisolated static func report(for error: any Error, instance: Instance?) -> ErrorReport {
        ErrorReport(error: error, instance: instance)
    }

    /// Runs a launch with a session from `makeSession`. The work runs in its own task, so `stop(_:)` can cancel it.
    func launch(
        _ instance: Instance,
        metadataMode: MetadataMode,
        join: JoinTarget?,
        events: @escaping @Sendable (LaunchEvent) -> Void,
        progress: ProgressManager,
        makeSession: @escaping @Sendable () async throws -> LaunchSession
    ) async throws -> Int32 {
        let services = services
        let game = try services.runningGames.begin(instance)
        let task = Task.detached {
            defer { services.runningGames.end(game) }
            let session = try await makeSession()
            let request = LaunchPipeline.Request(instance: instance, session: session, metadataMode: metadataMode, join: join)
            let log = LaunchLog(censor: LogCensor(session: session), send: events)
            return try await LaunchPipeline(services: services).run(request, game: game, log: log, progress: progress)
        }
        game.attach(task)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            game.stop()
        }
    }
}
