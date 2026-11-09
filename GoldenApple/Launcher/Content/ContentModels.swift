import Foundation

nonisolated enum ContentProvider: String, Codable, CaseIterable, Sendable {
    case modrinth
    case curseForge

    var displayName: String {
        switch self {
        case .modrinth: "Modrinth"
        case .curseForge: "CurseForge"
        }
    }
}

nonisolated enum ContentKind: String, Codable, CaseIterable, Sendable {
    case mod
    case resourcePack
    case shaderPack
    case modpack

    /// The folder below `Minecraft/` that holds files of this kind. Modpacks become their own instance.
    var gameFolderName: String? {
        switch self {
        case .mod: "mods"
        case .resourcePack: "resourcepacks"
        case .shaderPack: "shaderpacks"
        case .modpack: nil
        }
    }

    var modrinthProjectType: String {
        switch self {
        case .mod: "mod"
        case .resourcePack: "resourcepack"
        case .shaderPack: "shader"
        case .modpack: "modpack"
        }
    }

    var curseForgeClassID: Int {
        switch self {
        case .mod: 6
        case .resourcePack: 12
        case .shaderPack: 6552
        case .modpack: 4471
        }
    }

    init?(modrinthProjectType: String) {
        guard let kind = Self.allCases.first(where: { $0.modrinthProjectType == modrinthProjectType }) else {
            return nil
        }
        self = kind
    }

    init?(curseForgeClassID: Int) {
        guard let kind = Self.allCases.first(where: { $0.curseForgeClassID == curseForgeClassID }) else {
            return nil
        }
        self = kind
    }

    /// Search results are filtered by loader only for mods.
    var searchFiltersByLoader: Bool {
        self == .mod
    }

    /// Version lists are filtered by loader for mods and modpacks. Resource and shader packs do not depend on the mod loader.
    var versionsFilterByLoader: Bool {
        self == .mod || self == .modpack
    }
}

/// A project on Modrinth or CurseForge.
nonisolated struct ContentProject: Hashable, Identifiable, Sendable {
    let provider: ContentProvider
    /// The Modrinth project ID, or the CurseForge mod ID as text.
    let projectID: String
    let slug: String
    let title: String
    let summary: String
    let author: String
    let downloads: Int
    let iconURL: URL?
    let pageURL: URL?
    let kind: ContentKind

    var id: String { "\(provider.rawValue):\(projectID)" }
}

nonisolated enum ContentReleaseType: String, Codable, Sendable {
    case release
    case beta
    case alpha
}

/// A downloadable file of a version. CurseForge files without `downloadURL` must be downloaded by hand.
nonisolated struct ContentFile: Hashable, Sendable {
    let fileName: String
    let downloadURL: URL?
    let size: Int64?
    let sha1: String?
    let sha512: String?

    /// SHA-512 when known, else SHA-1.
    var checksum: Checksum? {
        if let sha512 = sha512.nonEmpty {
            return Checksum(.sha512, sha512)
        }
        return sha1.nonEmpty.map { Checksum(.sha1, $0) }
    }
}

nonisolated struct ContentDependency: Hashable, Sendable {
    enum Kind: Sendable {
        case required
        case optional
        case incompatible
        case embedded
        case other
    }

    let projectID: String?
    /// A specific version of the dependency. Without it, the best version for the instance is used.
    let versionID: String?
    let kind: Kind
}

/// A Modrinth version or a CurseForge file.
nonisolated struct ContentVersion: Hashable, Identifiable, Sendable {
    let provider: ContentProvider
    /// The Modrinth version ID, or the CurseForge file ID as text.
    let id: String
    let projectID: String
    let name: String
    let versionNumber: String
    let releaseType: ContentReleaseType
    let published: Date
    let gameVersions: [String]
    let loaders: [String]
    /// The primary file, else the first file. Nil when the version has no files.
    let file: ContentFile?
    let dependencies: [ContentDependency]

    var requiredDependencies: [ContentDependency] {
        dependencies.filter { $0.kind == .required }
    }

    /// The newest release, else the newest version of any type.
    static func best(of versions: [ContentVersion]) -> ContentVersion? {
        let newestFirst = versions.sorted { $0.published > $1.published }
        return newestFirst.first { $0.releaseType == .release } ?? newestFirst.first
    }
}

nonisolated struct ContentSearchPage: Sendable {
    let projects: [ContentProject]
    let totalCount: Int
}

/// A file the launcher may not download. The player downloads it from `pageURL` and puts it at `destination`.
nonisolated struct BlockedDownload: Hashable, Sendable {
    let title: String
    let fileName: String
    let pageURL: URL
    let destination: URL
}

nonisolated struct ContentInstallResult: Sendable {
    let installed: [InstalledContentEntry]
    let blocked: [BlockedDownload]
}

nonisolated struct ModpackResult: Sendable {
    let instance: Instance
    let blocked: [BlockedDownload]
    /// Files copied from the pack's override folders into `Minecraft/`.
    let overrideFileCount: Int
}
