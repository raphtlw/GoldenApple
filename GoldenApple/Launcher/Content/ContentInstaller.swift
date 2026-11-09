import Foundation
import os

/// Installs a project into an instance together with its required dependencies.
nonisolated struct ContentInstaller: Sendable {
    /// One file to put into the instance.
    private struct PlannedFile {
        let project: ContentProject
        let version: ContentVersion
        let file: ContentFile
        /// Relative to `Minecraft/`.
        let path: String
    }

    private enum Weight {
        static let planning = 1
        static let downloads = 9
    }

    let services: LauncherServices

    /// Uses `version`, else the best version for the instance. Required dependencies use the version they name,
    /// else their best version. Projects that are already installed are skipped as dependencies.
    func install(
        _ project: ContentProject,
        version: ContentVersion?,
        into instance: Instance,
        subprogress: consuming Subprogress? = nil
    ) async throws -> ContentInstallResult {
        guard project.kind != .modpack else {
            throw LauncherError.modpackNeedsOwnInstance(project.title)
        }
        let progress = ProgressManager.start(subprogress, totalCount: Weight.planning + Weight.downloads)
        let instance = try services.instances.current(instance)
        let plan = try await plan(project, version: version, for: instance)
        progress.complete(count: Weight.planning)

        var downloads: [DownloadItem] = []
        var entries: [InstalledContentEntry] = []
        var blocked: [BlockedDownload] = []
        for planned in plan {
            let destination = try FileSystem.safeChild(planned.path, of: instance.gameFolder)
            guard let url = planned.file.downloadURL else {
                blocked.append(try Self.blockedDownload(planned, destination: destination))
                continue
            }
            downloads.append(DownloadItem(url: url, destination: destination, checksum: planned.file.checksum, size: planned.file.size))
            entries.append(InstalledContentEntry(
                provider: planned.project.provider,
                projectID: planned.project.projectID,
                versionID: planned.version.id,
                title: planned.project.title,
                versionNumber: planned.version.versionNumber,
                path: planned.path,
                sha1: planned.file.sha1
            ))
        }
        try await services.downloads.download(downloads, subprogress: progress.subprogress(assigningCount: Weight.downloads))
        try services.installedContent.record(entries, in: instance)
        for entry in entries {
            LauncherLog.content.info("Installed \(entry.path, privacy: .public) into \(instance.id, privacy: .public)")
        }
        return ContentInstallResult(installed: entries, blocked: blocked)
    }

    // MARK: Planning

    /// The project first, then its required dependencies, breadth first. Installed projects are skipped as dependencies.
    private func plan(_ project: ContentProject, version: ContentVersion?, for instance: Instance) async throws -> [PlannedFile] {
        let source = services.contentSource(project.provider)
        let target = ContentTarget(instance)
        let installed = try services.installedContent.entries(of: instance).filter { $0.provider == project.provider }
        var skipped = Set(installed.map(\.projectID))
        skipped.insert(project.projectID)

        var queue = [(project, try await resolvedVersion(version, of: project, source: source, target: target))]
        var plan: [PlannedFile] = []
        while !queue.isEmpty {
            let (project, version) = queue.removeFirst()
            plan.append(try Self.plannedFile(project, version: version))
            for dependency in version.requiredDependencies {
                guard let resolved = try await resolve(dependency, source: source, target: target, skipping: skipped) else {
                    continue
                }
                skipped.insert(resolved.project.projectID)
                queue.append((resolved.project, resolved.version))
            }
        }
        return plan
    }

    /// The project and version of a dependency, or nil when it is skipped.
    private func resolve(
        _ dependency: ContentDependency,
        source: any ContentSource,
        target: ContentTarget,
        skipping skippedProjectIDs: Set<String>
    ) async throws -> (project: ContentProject, version: ContentVersion)? {
        var pinnedVersion: ContentVersion?
        var projectID = dependency.projectID
        if projectID == nil, let versionID = dependency.versionID {
            pinnedVersion = try await source.version(versionID, projectID: nil)
            projectID = pinnedVersion?.projectID
        }
        guard let projectID, !skippedProjectIDs.contains(projectID) else {
            return nil
        }
        let project = try await source.project(projectID)
        guard project.kind != .modpack else {
            return nil
        }
        if pinnedVersion == nil, let versionID = dependency.versionID {
            pinnedVersion = try await source.version(versionID, projectID: projectID)
        }
        return (project, try await resolvedVersion(pinnedVersion, of: project, source: source, target: target))
    }

    private func resolvedVersion(_ version: ContentVersion?, of project: ContentProject, source: any ContentSource, target: ContentTarget) async throws -> ContentVersion {
        if let version {
            return version
        }
        return try await source.bestVersion(of: project, target: target)
    }

    private static func plannedFile(_ project: ContentProject, version: ContentVersion) throws -> PlannedFile {
        guard let file = version.file, let folder = project.kind.gameFolderName else {
            throw LauncherError.contentVersionHasNoFile(title: project.title, version: version.versionNumber)
        }
        guard !file.fileName.contains("/") else {
            throw LauncherError.unsafePath(file.fileName)
        }
        return PlannedFile(project: project, version: version, file: file, path: "\(folder)/\(file.fileName)")
    }

    private static func blockedDownload(_ planned: PlannedFile, destination: URL) throws -> BlockedDownload {
        guard let pageURL = CurseForgeClient.downloadPage(projectPage: planned.project.pageURL, fileID: planned.version.id) else {
            throw LauncherError.contentVersionHasNoFile(title: planned.project.title, version: planned.version.versionNumber)
        }
        return BlockedDownload(title: planned.project.title, fileName: planned.file.fileName, pageURL: pageURL, destination: destination)
    }
}
