import Foundation

/// A library object from a version document.
nonisolated struct Library: Decodable, Hashable, Sendable {
    /// `group:artifact:version[:classifier][@extension]`
    let name: String
    /// Maven repository base. Nil means the default library server.
    let url: String?
    let downloads: LibraryDownloads?
    /// OS key to classifier. A classifier can contain `${arch}`.
    let natives: [String: String]?
    let extract: ExtractRules?
    let rules: [PlatformRule]?

    var coordinate: MavenCoordinate? {
        MavenCoordinate(name)
    }
}

nonisolated struct LibraryDownloads: Decodable, Hashable, Sendable {
    let artifact: DownloadArtifact?
    let classifiers: [String: DownloadArtifact]?
}

nonisolated struct DownloadArtifact: Decodable, Hashable, Sendable {
    let url: String?
    let sha1: String?
    let size: Int64?
    let path: String?
}

nonisolated struct ExtractRules: Decodable, Hashable, Sendable {
    let exclude: [String]?
}

nonisolated struct PlatformRule: Decodable, Hashable, Sendable {
    enum Action: String, Decodable, Sendable {
        case allow
        case disallow
    }

    struct OperatingSystem: Decodable, Hashable, Sendable {
        let name: String?
    }

    let action: Action
    let os: OperatingSystem?
}

/// A `+agents` entry: a library jar passed as `-javaagent:<jar>[=argument]`.
nonisolated struct JavaAgent: Decodable, Hashable, Sendable {
    let library: Library
    let argument: String?

    private enum CodingKeys: String, CodingKey {
        case argument
    }

    init(from decoder: any Decoder) throws {
        library = try Library(from: decoder)
        argument = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .argument)
    }
}
