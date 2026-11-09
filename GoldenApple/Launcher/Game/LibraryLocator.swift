import Foundation
import os

/// Where a library file lives on disk and where to download it.
nonisolated struct LibraryFile: Hashable, Sendable {
    let localFile: URL
    let downloadURL: URL
    let checksum: Checksum?
    let size: Int64?

    var downloadItem: DownloadItem {
        DownloadItem(url: downloadURL, destination: localFile, checksum: checksum, size: size)
    }
}

/// Maps library objects to files below `Libraries/`. The game jar is the exception:
/// it lives at `Versions/net.minecraft/<version>/client.jar`.
nonisolated struct LibraryLocator: Sendable {
    let paths: LauncherPaths
    let libraryBaseURL: URL

    /// The main jar of a library. Nil when the library name cannot be parsed.
    func artifact(of library: Library) -> LibraryFile? {
        guard let coordinate = library.coordinate else {
            LauncherLog.metadata.error("Ignoring library with invalid name \(library.name, privacy: .public)")
            return nil
        }
        return file(for: coordinate, of: library, download: library.downloads?.artifact)
    }

    /// The natives jar of a library for this Mac. Nil when the library has no natives for `osx-arm64`.
    func nativesArtifact(of library: Library) -> LibraryFile? {
        guard let classifier = PlatformRules.nativeClassifier(library), let coordinate = library.coordinate else {
            return nil
        }
        return file(for: coordinate.withClassifier(classifier), of: library, download: library.downloads?.classifiers?[classifier])
    }

    /// Every file a launch needs: libraries, natives, Maven files, agents and the game jar.
    func downloadItems(for profile: LaunchProfile) -> [DownloadItem] {
        let jars = (profile.libraries + profile.mavenFiles + profile.agents.map(\.library)).compactMap(artifact(of:))
        let natives = profile.nativeLibraries.compactMap(nativesArtifact(of:))
        let gameJar = profile.mainJar.flatMap(artifact(of:))
        return (jars + natives + [gameJar].compactMap { $0 }).map(\.downloadItem)
    }

    /// Library jars in profile order, then the game jar.
    func classPath(for profile: LaunchProfile) -> [URL] {
        let gameJar = profile.mainJar.flatMap(artifact(of:))
        return (profile.libraries.compactMap(artifact(of:)) + [gameJar].compactMap { $0 }).map(\.localFile)
    }

    private func file(for coordinate: MavenCoordinate, of library: Library, download: DownloadArtifact?) -> LibraryFile {
        let localFile = coordinate.isGameJar
            ? paths.clientJar(minecraftVersion: coordinate.version)
            : paths.libraries.appending(path: coordinate.relativePath)
        return LibraryFile(
            localFile: localFile,
            downloadURL: downloadURL(for: coordinate, of: library, download: download),
            checksum: download?.sha1.map { Checksum(.sha1, $0) },
            size: download?.size
        )
    }

    /// `downloads.artifact.url` when present, else the repository `url` or the default library server plus the Maven path.
    private func downloadURL(for coordinate: MavenCoordinate, of library: Library, download: DownloadArtifact?) -> URL {
        if let text = download?.url.nonEmpty, let url = URL(string: text) {
            return url
        }
        let repository = library.url.nonEmpty.flatMap(URL.init(string:)) ?? libraryBaseURL
        return repository.appending(path: coordinate.relativePath)
    }
}
