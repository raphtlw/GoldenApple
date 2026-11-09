import Foundation

/// A Modrinth modpack (`.mrpack`): `modrinth.index.json` plus `overrides/` and `client-overrides/`.
nonisolated struct ModrinthModpack: ModpackFormat {
    private static let indexFileName = "modrinth.index.json"
    private static let overrideFolders = ["overrides", "client-overrides"]
    private static let loaderKeys: [(key: String, loader: ModLoader)] = [
        ("fabric-loader", .fabric),
        ("quilt-loader", .quilt),
        ("forge", .forge),
        ("neoforge", .neoForge),
    ]

    let index: ModrinthPackIndex
    let requirements: ModpackRequirements

    /// Returns nil when the folder has no `modrinth.index.json`.
    init?(extractedFolder: URL) throws {
        guard let index = try ModpackReader.manifest(ModrinthPackIndex.self, named: Self.indexFileName, in: extractedFolder) else {
            return nil
        }
        try self.init(index: index)
    }

    init(index: ModrinthPackIndex) throws {
        guard index.formatVersion == 1 else {
            throw LauncherError.invalidModpack("\(Self.indexFileName) uses format version \(index.formatVersion).")
        }
        guard index.game == "minecraft" else {
            throw LauncherError.invalidModpack("the pack is for the game “\(index.game)”.")
        }
        guard let minecraftVersion = index.dependencies["minecraft"].nonEmpty else {
            throw LauncherError.invalidModpack("\(Self.indexFileName) does not name a Minecraft version.")
        }
        let loaders = Self.loaderKeys.compactMap { key, loader in
            index.dependencies[key].nonEmpty.map { (loader: loader, version: $0) }
        }
        guard loaders.count <= 1 else {
            throw LauncherError.invalidModpack("the pack needs more than one mod loader.")
        }
        self.index = index
        requirements = ModpackRequirements(
            name: index.name,
            minecraftVersion: minecraftVersion,
            loader: loaders.first?.loader,
            loaderVersion: loaders.first?.version
        )
    }

    /// Files whose `env.client` is `unsupported` are skipped. Each path must stay inside `Minecraft/`.
    func installFiles(
        into instance: Instance,
        extractedFolder: URL,
        services: LauncherServices,
        subprogress: consuming Subprogress?
    ) async throws -> ModpackFilesOutcome {
        let items = try downloadItems(gameFolder: instance.gameFolder)
        try await services.downloads.download(items, subprogress: subprogress)
        var overrideFileCount = 0
        for folder in Self.overrideFolders {
            overrideFileCount += try await ModpackOverrides.copy(folder, from: extractedFolder, into: instance.gameFolder)
        }
        return ModpackFilesOutcome(blocked: [], overrideFileCount: overrideFileCount)
    }

    func downloadItems(gameFolder: URL) throws -> [DownloadItem] {
        try index.files.filter(\.isForClient).map { file in
            let destination = try FileSystem.safeChild(file.path, of: gameFolder)
            guard let url = file.downloads.first else {
                throw LauncherError.invalidModpack("\(file.path) has no download address.")
            }
            let checksum = ContentFile(fileName: file.path, downloadURL: url, size: file.fileSize, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"]).checksum
            return DownloadItem(url: url, destination: destination, checksum: checksum, size: file.fileSize)
        }
    }
}

/// The contents of `modrinth.index.json`.
nonisolated struct ModrinthPackIndex: Decodable, Sendable {
    struct File: Decodable, Sendable {
        struct Environment: Decodable, Sendable {
            let client: String?
            let server: String?
        }

        let path: String
        let hashes: [String: String]
        let env: Environment?
        let downloads: [URL]
        let fileSize: Int64?

        var isForClient: Bool {
            env?.client != "unsupported"
        }
    }

    let formatVersion: Int
    let game: String
    let versionId: String
    let name: String
    let summary: String?
    let files: [File]
    let dependencies: [String: String]
}
