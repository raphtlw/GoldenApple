import Foundation

/// `index.json`: every package on the metadata server.
nonisolated struct PackageIndex: Decodable, Sendable {
    struct Package: Decodable, Sendable {
        let uid: String
        let name: String?
        /// SHA-256 of `<uid>/index.json`.
        let sha256: String
    }

    let formatVersion: Int
    let packages: [Package]
}

/// `<uid>/index.json`: every version of one package.
nonisolated struct VersionList: Decodable, Sendable {
    let formatVersion: Int
    let uid: String
    let name: String?
    let versions: [VersionListEntry]
}

nonisolated struct VersionListEntry: Decodable, Sendable {
    let version: String
    /// `release`, `snapshot`, `old_beta`, `old_alpha` or another value. Some packages leave it out.
    let type: String?
    let releaseTime: Date
    let isRecommended: Bool
    let isVolatile: Bool
    let requires: [Requirement]
    let conflicts: [Requirement]
    /// SHA-256 of `<uid>/<version>.json`.
    let sha256: String

    private enum CodingKeys: String, CodingKey {
        case version, type, releaseTime, recommended, volatile, requires, conflicts, sha256
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        releaseTime = try container.decode(Date.self, forKey: .releaseTime)
        isRecommended = try container.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
        isVolatile = try container.decodeIfPresent(Bool.self, forKey: .volatile) ?? false
        requires = try container.decodeIfPresent([Requirement].self, forKey: .requires) ?? []
        conflicts = try container.decodeIfPresent([Requirement].self, forKey: .conflicts) ?? []
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

/// A dependency or conflict on another package.
nonisolated struct Requirement: Codable, Hashable, Sendable {
    let uid: String
    /// A hard version requirement.
    var equals: String?
    /// A preferred version.
    var suggests: String?
}

/// `<uid>/<version>.json`: everything one component adds to a launch.
nonisolated struct VersionDocument: Decodable, Sendable {
    let formatVersion: Int
    let uid: String
    let version: String
    let name: String?
    let type: String?
    let releaseTime: Date?
    /// Components apply in ascending order.
    let order: Int
    let requires: [Requirement]
    let conflicts: [Requirement]
    let isVolatile: Bool
    let mainClass: String?
    let minecraftArguments: String?
    let jvmArguments: [String]
    let traits: [String]
    let tweakers: [String]
    let mainJar: Library?
    let libraries: [Library]
    /// Downloaded but not put on the class path, for example Forge installers.
    let mavenFiles: [Library]
    let agents: [JavaAgent]
    let assetIndex: AssetIndexReference?
    let compatibleJavaMajors: [Int]
    let compatibleJavaName: String?
    let runtimes: [JavaRuntime]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, uid, version, name, type, releaseTime, order, requires, conflicts
        case isVolatile = "volatile"
        case mainClass, minecraftArguments
        case jvmArguments = "+jvmArgs"
        case traits = "+traits"
        case tweakers = "+tweakers"
        case mainJar, libraries, mavenFiles
        case agents = "+agents"
        case assetIndex, compatibleJavaMajors, compatibleJavaName, runtimes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        uid = try container.decode(String.self, forKey: .uid)
        version = try container.decode(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        releaseTime = try container.decodeIfPresent(Date.self, forKey: .releaseTime)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        requires = try container.decodeIfPresent([Requirement].self, forKey: .requires) ?? []
        conflicts = try container.decodeIfPresent([Requirement].self, forKey: .conflicts) ?? []
        isVolatile = try container.decodeIfPresent(Bool.self, forKey: .isVolatile) ?? false
        mainClass = try container.decodeIfPresent(String.self, forKey: .mainClass)
        minecraftArguments = try container.decodeIfPresent(String.self, forKey: .minecraftArguments)
        jvmArguments = try container.decodeIfPresent([String].self, forKey: .jvmArguments) ?? []
        traits = try container.decodeIfPresent([String].self, forKey: .traits) ?? []
        tweakers = try container.decodeIfPresent([String].self, forKey: .tweakers) ?? []
        mainJar = try container.decodeIfPresent(Library.self, forKey: .mainJar)
        libraries = try container.decodeIfPresent([Library].self, forKey: .libraries) ?? []
        mavenFiles = try container.decodeIfPresent([Library].self, forKey: .mavenFiles) ?? []
        agents = try container.decodeIfPresent([JavaAgent].self, forKey: .agents) ?? []
        assetIndex = try container.decodeIfPresent(AssetIndexReference.self, forKey: .assetIndex)
        compatibleJavaMajors = try container.decodeIfPresent([Int].self, forKey: .compatibleJavaMajors) ?? []
        compatibleJavaName = try container.decodeIfPresent(String.self, forKey: .compatibleJavaName)
        runtimes = try container.decodeIfPresent([JavaRuntime].self, forKey: .runtimes) ?? []
    }
}

nonisolated struct AssetIndexReference: Codable, Hashable, Sendable {
    let id: String
    let sha1: String?
    let size: Int64?
    let totalSize: Int64?
    let url: URL
}
