import Foundation
import os

extension GoldenAppleLauncher {
    private enum ModpackWeight {
        static let packDownload = 20
        static let packImport = 80
        static let reading = 5
        static let instance = 10
        static let files = 85
    }

    /// Searches a provider. With an instance, results are limited to its Minecraft version, and mods also to its loaders.
    func search(
        _ query: String,
        provider: ContentProvider,
        kind: ContentKind,
        for instance: Instance?,
        offset: Int = 0,
        limit: Int = 20
    ) async throws -> ContentSearchPage {
        let target = try instance.map { ContentTarget(try services.instances.current($0)) }
        return try await services.contentSource(provider).search(query, kind: kind, target: target, offset: offset, limit: limit)
    }

    /// The versions of the project that fit the instance, newest first.
    func versions(of project: ContentProject, for instance: Instance) async throws -> [ContentVersion] {
        let target = ContentTarget(try services.instances.current(instance))
        let versions = try await services.contentSource(project.provider).versions(of: project, target: target)
        return versions.sorted { $0.published > $1.published }
    }

    /// Installs the project with its required dependencies. Without `version`, the best version for the instance is used.
    func install(
        _ project: ContentProject,
        version: ContentVersion? = nil,
        into instance: Instance,
        subprogress: consuming Subprogress? = nil
    ) async throws -> ContentInstallResult {
        try await ContentInstaller(services: services).install(project, version: version, into: instance, subprogress: subprogress)
    }

    /// Installs Essential from Modrinth. An instance without a mod loader first gets the recommended Fabric version.
    func installEssential(into instance: Instance, subprogress: consuming Subprogress? = nil) async throws -> ContentInstallResult {
        var current = try services.instances.current(instance)
        if current.loader == nil {
            try await setLoader(.fabric, version: nil, for: current)
            current = try services.instances.current(current)
        }
        let essential = try await services.modrinth.project(ModrinthClient.essentialProjectID)
        return try await install(essential, version: nil, into: current, subprogress: subprogress)
    }

    func installedContent(of instance: Instance) throws -> [InstalledContentEntry] {
        try services.installedContent.entries(of: instance)
    }

    /// Deletes the file of the entry and removes it from `Installed Content.json`.
    func uninstall(_ entry: InstalledContentEntry, from instance: Instance) throws {
        try services.installedContent.remove(entry, from: services.instances.current(instance))
    }

    /// Downloads the modpack file of `version`, else of the best version, verifies it, and imports it as a new instance.
    func installModpack(
        _ project: ContentProject,
        version: ContentVersion? = nil,
        name: String? = nil,
        subprogress: consuming Subprogress? = nil
    ) async throws -> ModpackResult {
        let progress = ProgressManager.start(subprogress, totalCount: ModpackWeight.packDownload + ModpackWeight.packImport)
        guard project.kind == .modpack else {
            throw LauncherError.invalidModpack("\(project.title) is not a modpack.")
        }
        let source = services.contentSource(project.provider)
        let resolvedVersion = if let version { version } else { try await source.bestVersion(of: project, target: nil) }
        guard let file = resolvedVersion.file, !file.fileName.contains("/") else {
            throw LauncherError.contentVersionHasNoFile(title: project.title, version: resolvedVersion.versionNumber)
        }
        guard let url = file.downloadURL else {
            let pageURL = CurseForgeClient.downloadPage(projectPage: project.pageURL, fileID: resolvedVersion.id)
            throw pageURL.map { LauncherError.modpackDownloadBlocked(title: project.title, pageURL: $0) }
                ?? LauncherError.contentVersionHasNoFile(title: project.title, version: resolvedVersion.versionNumber)
        }

        let folder = paths.downloads.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileSystem.removeIfPresent(folder) }
        let packFile = folder.appending(path: file.fileName)
        try await services.downloads.download(
            [DownloadItem(url: url, destination: packFile, checksum: file.checksum, size: file.size)],
            subprogress: progress.subprogress(assigningCount: ModpackWeight.packDownload)
        )
        return try await importModpack(
            at: packFile,
            name: name.nonEmpty ?? project.title,
            subprogress: progress.subprogress(assigningCount: ModpackWeight.packImport)
        )
    }

    /// Imports a Modrinth `.mrpack` or a CurseForge zip as a new instance. When any step fails, the new instance is deleted.
    func importModpack(at file: URL, name: String? = nil, subprogress: consuming Subprogress? = nil) async throws -> ModpackResult {
        let progress = ProgressManager.start(subprogress, totalCount: ModpackWeight.reading + ModpackWeight.instance + ModpackWeight.files)
        let extractedFolder = paths.downloads.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileSystem.removeIfPresent(extractedFolder) }
        let pack = try await ModpackReader.read(file, extractingTo: extractedFolder)
        progress.complete(count: ModpackWeight.reading)

        let requirements = pack.requirements
        let instance = try await createInstance(
            name: name.nonEmpty ?? requirements.name,
            minecraftVersion: requirements.minecraftVersion,
            loader: requirements.loader,
            loaderVersion: requirements.loaderVersion
        )
        progress.complete(count: ModpackWeight.instance)
        do {
            let outcome = try await pack.installFiles(
                into: instance,
                extractedFolder: extractedFolder,
                services: services,
                subprogress: progress.subprogress(assigningCount: ModpackWeight.files)
            )
            LauncherLog.content.info("Imported modpack \(instance.id, privacy: .public) with \(outcome.overrideFileCount) override files")
            return ModpackResult(instance: try services.instances.current(instance), blocked: outcome.blocked, overrideFileCount: outcome.overrideFileCount)
        } catch {
            LauncherLog.content.error("Modpack import failed, deleting \(instance.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileSystem.removeIfPresent(instance.folder)
            throw error
        }
    }
}
