import Foundation
import os

/// Installs downloadable Java runtimes into `Java/<name>/`.
nonisolated struct JavaRuntimeInstaller: Sendable {
    let paths: LauncherPaths
    let http: HTTPClient
    let downloads: DownloadQueue

    /// Installs `runtime` into `Java/<folderName>/` and returns its `bin/java`.
    func install(_ runtime: JavaRuntime, folderName: String, subprogress: consuming Subprogress? = nil) async throws -> URL {
        guard let safeName = FileSystem.safeFolderName(folderName) else {
            throw LauncherError.invalidName(folderName)
        }
        let folder = paths.javaRuntime(safeName)
        LauncherLog.java.info("Installing Java runtime \(runtime.name, privacy: .public) into \(folder.path, privacy: .public)")
        switch runtime.downloadType {
        case "manifest":
            try await installManifest(runtime, into: folder, subprogress: subprogress)
        case "archive":
            try await installArchive(runtime, into: folder, subprogress: subprogress)
        default:
            throw LauncherError.unsupportedArchive(runtime.url.lastPathComponent)
        }
        try linkHomeContents(in: folder)
        let binary = folder.appending(path: "bin/java")
        guard FileSystem.exists(binary) else {
            throw LauncherError.javaRuntimeMissingBinary(runtime.name)
        }
        return binary
    }

    // MARK: Manifest runtimes

    private func installManifest(_ runtime: JavaRuntime, into folder: URL, subprogress: consuming Subprogress?) async throws {
        let data = try await http.data(from: runtime.url)
        try runtime.expectedChecksum?.verify(data, name: runtime.url.lastPathComponent)
        let manifest = try JSONFiles.decode(RuntimeManifest.self, from: data, name: runtime.url.absoluteString)

        var items: [DownloadItem] = []
        var executables: [URL] = []
        var links: [(file: URL, target: String)] = []
        for (path, entry) in manifest.files {
            let file = try FileSystem.safeChild(path, of: folder)
            switch entry.type {
            case "directory":
                try FileSystem.createFolder(file)
            case "file":
                guard let raw = entry.downloads?.raw, let text = raw.url, let url = URL(string: text) else {
                    continue
                }
                items.append(DownloadItem(url: url, destination: file, checksum: raw.sha1.map { Checksum(.sha1, $0) }, size: raw.size))
                if entry.executable == true {
                    executables.append(file)
                }
            case "link":
                if let target = entry.target {
                    links.append((file, target))
                }
            default:
                LauncherLog.java.info("Ignoring runtime entry \(path, privacy: .public) of type \(entry.type, privacy: .public)")
            }
        }

        try await downloads.download(items, subprogress: subprogress)
        for file in executables {
            try FileSystem.setExecutable(file)
        }
        for link in links {
            try FileSystem.createSymbolicLink(at: link.file, pointingTo: link.target)
        }
    }

    // MARK: Archive runtimes

    private func installArchive(_ runtime: JavaRuntime, into folder: URL, subprogress: consuming Subprogress?) async throws {
        let archive = paths.javaArchives.appending(path: runtime.url.lastPathComponent)
        try await downloads.download(
            [DownloadItem(url: runtime.url, destination: archive, checksum: runtime.expectedChecksum)],
            subprogress: subprogress
        )

        let staging = paths.javaArchives.appending(path: "\(UUID().uuidString) Extracting", directoryHint: .isDirectory)
        defer { try? FileSystem.removeIfPresent(staging) }
        try await ArchiveExtractor.extract(archive, to: staging)

        // An archive with one top-level folder puts that folder's contents into the runtime folder.
        let topLevel = try FileSystem.contents(of: staging).filter { !$0.lastPathComponent.hasPrefix(".") }
        let source = topLevel.count == 1 && FileSystem.isDirectory(topLevel[0]) ? topLevel[0] : staging
        try FileSystem.move(source, to: folder)
    }

    // MARK: macOS bundle layout

    /// macOS runtimes keep `bin/java` inside `Contents/Home`. When the runtime folder has no `bin/java`,
    /// this links every entry of that `Contents/Home` into the runtime folder.
    private func linkHomeContents(in folder: URL) throws {
        guard !FileSystem.exists(folder.appending(path: "bin/java")), let home = try homeFolder(in: folder) else {
            return
        }
        for entry in try FileSystem.contents(of: home.url) {
            let link = folder.appending(path: entry.lastPathComponent)
            guard !FileSystem.exists(link) else {
                continue
            }
            try FileSystem.createSymbolicLink(at: link, pointingTo: "\(home.relativePath)/\(entry.lastPathComponent)")
        }
    }

    /// `Contents/Home` or `<bundle>.bundle/Contents/Home` inside the runtime folder.
    private func homeFolder(in folder: URL) throws -> (url: URL, relativePath: String)? {
        var relativePaths = ["Contents/Home"]
        for item in try FileSystem.contents(of: folder) where item.pathExtension == "bundle" {
            relativePaths.append("\(item.lastPathComponent)/Contents/Home")
        }
        for relativePath in relativePaths {
            let url = folder.appending(path: relativePath, directoryHint: .isDirectory)
            if FileSystem.exists(url.appending(path: "bin/java")) {
                return (url, relativePath)
            }
        }
        return nil
    }
}
