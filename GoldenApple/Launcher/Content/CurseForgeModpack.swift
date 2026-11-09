import Foundation
import os

/// A CurseForge modpack zip: `manifest.json` plus an overrides folder. The files it lists are downloaded through the API.
nonisolated struct CurseForgeModpack: ModpackFormat {
    private static let manifestFileName = "manifest.json"

    /// Where the files of a pack go, and the files the launcher may not download.
    struct Placement {
        var downloads: [DownloadItem] = []
        var blocked: [BlockedDownload] = []
    }

    let manifest: CurseForgeManifest
    let requirements: ModpackRequirements

    /// Returns nil when the folder has no `manifest.json`.
    init?(extractedFolder: URL) throws {
        guard let manifest = try ModpackReader.manifest(CurseForgeManifest.self, named: Self.manifestFileName, in: extractedFolder) else {
            return nil
        }
        try self.init(manifest: manifest)
    }

    init(manifest: CurseForgeManifest) throws {
        guard manifest.manifestType == "minecraftModpack" else {
            throw LauncherError.invalidModpack("\(Self.manifestFileName) has the type “\(manifest.manifestType)”.")
        }
        guard manifest.manifestVersion == 1 else {
            throw LauncherError.invalidModpack("\(Self.manifestFileName) uses version \(manifest.manifestVersion).")
        }
        let minecraftVersion = manifest.minecraft.version
        let loaderEntry = manifest.minecraft.modLoaders.first(where: { $0.primary == true }) ?? manifest.minecraft.modLoaders.first
        let loader = try loaderEntry.map { try Self.parseLoaderID($0.id, minecraftVersion: minecraftVersion) }
        self.manifest = manifest
        requirements = ModpackRequirements(
            name: manifest.name,
            minecraftVersion: minecraftVersion,
            loader: loader?.loader,
            loaderVersion: loader?.version
        )
    }

    /// Splits a loader ID such as `forge-47.2.0` into the loader and its version.
    /// A NeoForge ID can contain the Minecraft version, as in `neoforge-1.20.1-47.1.100`. That part is dropped.
    static func parseLoaderID(_ id: String, minecraftVersion: String) throws -> (loader: ModLoader, version: String) {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let loader = ModLoader(providerName: parts[0]), !parts[1].isEmpty else {
            throw LauncherError.invalidModpack("the mod loader “\(id)” is unknown.")
        }
        let minecraftPrefix = "\(minecraftVersion)-"
        let version = parts[1].hasPrefix(minecraftPrefix) ? String(parts[1].dropFirst(minecraftPrefix.count)) : parts[1]
        return (loader, version)
    }

    func installFiles(
        into instance: Instance,
        extractedFolder: URL,
        services: LauncherServices,
        subprogress: consuming Subprogress?
    ) async throws -> ModpackFilesOutcome {
        let fileIDs = manifest.files.filter(\.isRequired).map(\.fileID)
        let files = try await services.curseForge.files(fileIDs)
        let missingIDs = Set(fileIDs).subtracting(files.compactMap { Int($0.id) })
        guard missingIDs.isEmpty else {
            let list = missingIDs.sorted().map(String.init).joined(separator: ", ")
            throw LauncherError.invalidModpack("CurseForge does not know the files \(list).")
        }
        let modIDs = Set(files.compactMap { Int($0.projectID) })
        let mods = try await services.curseForge.mods(modIDs.sorted())
        let placement = try Self.place(files, mods: mods, gameFolder: instance.gameFolder)
        try await services.downloads.download(placement.downloads, subprogress: subprogress)
        let overrideFileCount = try await ModpackOverrides.copy(manifest.overrides ?? "overrides", from: extractedFolder, into: instance.gameFolder)
        return ModpackFilesOutcome(blocked: placement.blocked, overrideFileCount: overrideFileCount)
    }

    /// Puts each file into the game folder of its project class. Files without a download address become
    /// blocked downloads. Files of classes without a game folder, such as worlds, are skipped.
    static func place(_ files: [ContentVersion], mods: [CurseForgeMod], gameFolder: URL) throws -> Placement {
        let modsByID = Dictionary(mods.map { (String($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        var placement = Placement()
        for version in files {
            guard let file = version.file, let mod = modsByID[version.projectID] else {
                throw LauncherError.invalidModpack("CurseForge sent no project for the file \(version.id).")
            }
            guard let folder = mod.classId.flatMap(ContentKind.init(curseForgeClassID:))?.gameFolderName else {
                LauncherLog.content.info("Skipping \(file.fileName, privacy: .public): class \(mod.classId ?? 0) has no game folder")
                continue
            }
            let destination = try FileSystem.safeChild("\(folder)/\(file.fileName)", of: gameFolder)
            if let url = file.downloadURL {
                placement.downloads.append(DownloadItem(url: url, destination: destination, checksum: file.checksum, size: file.size))
            } else {
                guard let pageURL = CurseForgeClient.downloadPage(projectPage: mod.links?.websiteUrl, fileID: version.id) else {
                    throw LauncherError.contentVersionHasNoFile(title: mod.name, version: version.versionNumber)
                }
                placement.blocked.append(BlockedDownload(title: mod.name, fileName: file.fileName, pageURL: pageURL, destination: destination))
            }
        }
        return placement
    }
}

/// The contents of `manifest.json`.
nonisolated struct CurseForgeManifest: Decodable, Sendable {
    struct Minecraft: Decodable, Sendable {
        struct Loader: Decodable, Sendable {
            let id: String
            let primary: Bool?
        }

        let version: String
        let modLoaders: [Loader]
    }

    struct File: Decodable, Sendable {
        let projectID: Int
        let fileID: Int
        let required: Bool?

        /// Files without `required` are required.
        var isRequired: Bool {
            required ?? true
        }
    }

    let manifestType: String
    let manifestVersion: Int
    let name: String
    let version: String?
    let minecraft: Minecraft
    let files: [File]
    let overrides: String?
}
