import Foundation

/// What a modpack needs from its new instance.
nonisolated struct ModpackRequirements: Sendable {
    let name: String
    let minecraftVersion: String
    let loader: ModLoader?
    let loaderVersion: String?
}

/// What installing a modpack's files into its instance produced.
nonisolated struct ModpackFilesOutcome: Sendable {
    let blocked: [BlockedDownload]
    let overrideFileCount: Int
}

/// A modpack format whose archive is extracted to a folder.
nonisolated protocol ModpackFormat: Sendable {
    var requirements: ModpackRequirements { get }

    /// Downloads the pack's files into the instance and copies its override folders.
    func installFiles(
        into instance: Instance,
        extractedFolder: URL,
        services: LauncherServices,
        subprogress: consuming Subprogress?
    ) async throws -> ModpackFilesOutcome
}

nonisolated enum ModpackReader {
    /// Extracts the archive into `folder` and reads its Modrinth index or CurseForge manifest.
    static func read(_ archive: URL, extractingTo folder: URL) async throws -> any ModpackFormat {
        try await ArchiveExtractor.extract(archive, to: folder)
        if let pack = try ModrinthModpack(extractedFolder: folder) {
            return pack
        }
        if let pack = try CurseForgeModpack(extractedFolder: folder) {
            return pack
        }
        throw LauncherError.invalidModpack("it has no modrinth.index.json or manifest.json.")
    }

    /// Reads a manifest at the top of the extracted pack, or returns nil when the file does not exist.
    static func manifest<Manifest: Decodable>(_ type: Manifest.Type, named name: String, in folder: URL) throws -> Manifest? {
        let file = folder.appending(path: name)
        guard FileSystem.exists(file) else {
            return nil
        }
        return try JSONFiles.read(type, from: file)
    }
}

nonisolated enum ModpackOverrides {
    /// Copies every file below `folderName` of the extracted pack into `Minecraft/`, replacing existing files.
    /// Symbolic links are skipped. Returns the number of copied files.
    @concurrent
    static func copy(_ folderName: String, from extractedFolder: URL, into gameFolder: URL) async throws -> Int {
        let source = try FileSystem.safeChild(folderName, of: extractedFolder)
        guard FileSystem.isDirectory(source) else {
            return 0
        }
        var count = 0
        for relativePath in try FileSystem.relativeFilePaths(in: source) {
            let file = source.appending(path: relativePath)
            guard !FileSystem.isSymbolicLink(file) else {
                continue
            }
            try FileSystem.replace(try FileSystem.safeChild(relativePath, of: gameFolder), withCopyOf: file)
            count += 1
        }
        return count
    }
}
