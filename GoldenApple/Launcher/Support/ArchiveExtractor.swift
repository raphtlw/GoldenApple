import Foundation

/// Extracts zip archives (also `.jar` and `.mrpack`) with `ditto` and gzip tar archives with `tar`.
nonisolated enum ArchiveExtractor {
    enum Kind {
        case zip
        case gzipTar

        init?(fileName: String) {
            let name = fileName.lowercased()
            if name.hasSuffix(".zip") || name.hasSuffix(".jar") || name.hasSuffix(".mrpack") {
                self = .zip
            } else if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
                self = .gzipTar
            } else {
                return nil
            }
        }
    }

    static func extract(_ archive: URL, to destination: URL) async throws {
        guard let kind = Kind(fileName: archive.lastPathComponent) else {
            throw LauncherError.unsupportedArchive(archive.lastPathComponent)
        }
        try FileSystem.createFolder(destination)
        switch kind {
        case .zip:
            _ = try await ProcessRunner.runChecked(URL(filePath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, destination.path])
        case .gzipTar:
            _ = try await ProcessRunner.runChecked(URL(filePath: "/usr/bin/tar"), arguments: ["-xzf", archive.path, "-C", destination.path])
        }
    }
}
