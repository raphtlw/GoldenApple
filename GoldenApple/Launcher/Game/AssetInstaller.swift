import Foundation

/// The contents of an asset index file.
nonisolated struct AssetIndex: Decodable, Sendable {
    struct Object: Decodable, Sendable {
        let hash: String
        let size: Int64
    }

    /// Path in the game to object.
    let objects: [String: Object]
    /// Objects are also copied to `Assets/virtual/<id>/<path>`.
    let isVirtual: Bool
    /// Objects are also copied to `<game directory>/resources/<path>`.
    let mapsToResources: Bool

    private enum CodingKeys: String, CodingKey {
        case objects
        case isVirtual = "virtual"
        case mapsToResources = "map_to_resources"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objects = try container.decode([String: Object].self, forKey: .objects)
        isVirtual = try container.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        mapsToResources = try container.decodeIfPresent(Bool.self, forKey: .mapsToResources) ?? false
    }
}

/// Downloads asset indexes and objects, and copies objects for old versions that read them from plain paths.
nonisolated struct AssetInstaller: Sendable {
    let paths: LauncherPaths
    let resourceBaseURL: URL
    let downloads: DownloadQueue

    /// Downloads `Assets/indexes/<id>.json` when it is missing or damaged, then reads it.
    func downloadIndex(_ reference: AssetIndexReference) async throws -> AssetIndex {
        try await downloads.download([indexDownloadItem(reference)])
        return try loadIndex(reference)
    }

    /// Reads the index from disk without network access.
    func loadIndex(_ reference: AssetIndexReference) throws -> AssetIndex {
        let file = paths.assetIndexFile(id: reference.id)
        guard FileSystem.exists(file) else {
            throw LauncherError.metadataMissingOffline(file.path)
        }
        return try JSONFiles.read(AssetIndex.self, from: file)
    }

    func indexDownloadItem(_ reference: AssetIndexReference) -> DownloadItem {
        DownloadItem(
            url: reference.url,
            destination: paths.assetIndexFile(id: reference.id),
            checksum: reference.sha1.map { Checksum(.sha1, $0) },
            size: reference.size
        )
    }

    /// One item per unique object. Existing objects with the right size are skipped.
    func objectDownloadItems(_ index: AssetIndex) -> [DownloadItem] {
        var seen = Set<String>()
        return index.objects.values
            .filter { seen.insert($0.hash).inserted }
            .sorted { $0.hash < $1.hash }
            .map { object in
                DownloadItem(
                    url: resourceBaseURL.appending(path: "\(object.hash.prefix(2))/\(object.hash)"),
                    destination: paths.assetObject(hash: object.hash),
                    checksum: Checksum(.sha1, object.hash),
                    size: object.size,
                    skipsWhenSizeMatches: true
                )
            }
    }

    func downloadObjects(_ index: AssetIndex, subprogress: consuming Subprogress? = nil) async throws {
        try await downloads.download(objectDownloadItems(index), subprogress: subprogress)
    }

    /// Copies objects to `Assets/virtual/<id>/` and `<game directory>/resources/` when the index asks for it.
    /// Only missing files are copied.
    @concurrent
    func copyPlainFiles(_ index: AssetIndex, id: String, gameFolder: URL) async throws {
        var destinations: [URL] = []
        if index.isVirtual {
            destinations.append(paths.virtualAssets(id: id))
        }
        if index.mapsToResources {
            destinations.append(resourcesFolder(gameFolder))
        }
        for destination in destinations {
            for (path, object) in index.objects {
                try Task.checkCancellation()
                try FileSystem.copyIfMissing(paths.assetObject(hash: object.hash), to: try FileSystem.safeChild(path, of: destination))
            }
        }
    }

    /// The value of `${game_assets}`.
    func gameAssetsFolder(_ index: AssetIndex, id: String, gameFolder: URL) -> URL {
        if index.mapsToResources && !index.isVirtual {
            return resourcesFolder(gameFolder)
        }
        return paths.virtualAssets(id: id)
    }

    private func resourcesFolder(_ gameFolder: URL) -> URL {
        gameFolder.appending(path: "resources", directoryHint: .isDirectory)
    }
}
