import Foundation

/// Extracts native library jars into an instance's `Natives/` folder.
nonisolated struct NativesExtractor: Sendable {
    let libraries: LibraryLocator
    /// Each jar is unpacked here first, so excluded entries never reach `Natives/`.
    let stagingFolder: URL

    /// Replaces `folder` with the contents of the natives jars. Entries below an `extract.exclude` prefix are skipped,
    /// and `.jnilib` files are renamed to `.dylib`.
    @concurrent
    func extract(_ nativeLibraries: [Library], into folder: URL) async throws {
        try FileSystem.removeIfPresent(folder)
        try FileSystem.createFolder(folder)
        for library in nativeLibraries {
            guard let jar = libraries.nativesArtifact(of: library)?.localFile else {
                continue
            }
            try await extract(jar, excluding: library.extract?.exclude ?? [], into: folder)
        }
    }

    private func extract(_ jar: URL, excluding excludedPrefixes: [String], into folder: URL) async throws {
        let staging = stagingFolder.appending(path: "\(UUID().uuidString) Natives", directoryHint: .isDirectory)
        defer { try? FileSystem.removeIfPresent(staging) }
        try await ArchiveExtractor.extract(jar, to: staging)
        for path in try FileSystem.relativeFilePaths(in: staging) where !excludedPrefixes.contains(where: path.hasPrefix) {
            try FileSystem.move(staging.appending(path: path), to: try FileSystem.safeChild(Self.macOSName(path), of: folder))
        }
    }

    private static func macOSName(_ path: String) -> String {
        guard path.hasSuffix(".jnilib") else {
            return path
        }
        return path.dropLast(".jnilib".count) + ".dylib"
    }
}
