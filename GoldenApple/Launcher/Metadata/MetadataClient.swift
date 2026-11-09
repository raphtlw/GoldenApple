import Foundation

/// Whether metadata may come from the network.
nonisolated enum MetadataMode: Sendable {
    /// Download what is missing or out of date.
    case online
    /// Use only the files on disk. A missing file is an error.
    case offline
}

/// Loads package indexes, version lists and version documents from the metadata server and keeps them in `Versions/`.
actor MetadataClient {
    private static let acceptedFormatVersions = 0...1

    private let paths: LauncherPaths
    private let configuration: GoldenAppleConfiguration
    private let settings: SettingsStore
    private let http: HTTPClient
    private let httpCache: HTTPCache

    private var packageIndex: PackageIndex?
    private var versionLists: [String: VersionList] = [:]
    private var documents: [String: VersionDocument] = [:]

    init(paths: LauncherPaths, configuration: GoldenAppleConfiguration, settings: SettingsStore, http: HTTPClient, httpCache: HTTPCache) {
        self.paths = paths
        self.configuration = configuration
        self.settings = settings
        self.http = http
        self.httpCache = httpCache
    }

    /// The package index. Online, it is requested once per launcher run with a conditional request.
    func packageIndex(mode: MetadataMode) async throws -> PackageIndex {
        if let packageIndex {
            return packageIndex
        }
        let file = paths.packageIndexFile
        let data: Data = switch mode {
        case .online: try await httpCache.fetch(serverURL("index.json"), cachedIn: file)
        case .offline: try Self.readOffline(file)
        }
        let index = try decode(PackageIndex.self, from: data, file: file)
        try checkFormatVersion(index.formatVersion, file: file)
        packageIndex = index
        return index
    }

    func versionList(_ uid: String, mode: MetadataMode) async throws -> VersionList {
        if let list = versionLists[uid] {
            return list
        }
        let file = paths.versionListFile(uid)
        let data: Data
        switch mode {
        case .online:
            guard let package = try await packageIndex(mode: .online).packages.first(where: { $0.uid == uid }) else {
                throw LauncherError.unknownPackage(uid)
            }
            data = try await loadVerified(file, from: serverURL("\(uid)/index.json"), sha256: package.sha256)
        case .offline:
            data = try Self.readOffline(file)
        }
        let list = try decode(VersionList.self, from: data, file: file)
        try checkFormatVersion(list.formatVersion, file: file)
        versionLists[uid] = list
        return list
    }

    func versionDocument(_ uid: String, version: String, mode: MetadataMode) async throws -> VersionDocument {
        let key = "\(uid)/\(version)"
        if let document = documents[key] {
            return document
        }
        let file = paths.versionDocumentFile(uid: uid, version: version)
        let data: Data
        switch mode {
        case .online:
            guard let entry = try await versionList(uid, mode: .online).versions.first(where: { $0.version == version }) else {
                throw LauncherError.unknownVersion(uid: uid, version: version)
            }
            data = try await loadVerified(file, from: serverURL("\(uid)/\(version).json"), sha256: entry.sha256)
        case .offline:
            data = try Self.readOffline(file)
        }
        let document = try decode(VersionDocument.self, from: data, file: file)
        try checkFormatVersion(document.formatVersion, file: file)
        documents[key] = document
        return document
    }

    // MARK: Loading

    /// Uses the file on disk when its SHA-256 matches, else downloads, verifies and stores it.
    private func loadVerified(_ file: URL, from url: URL, sha256: String) async throws -> Data {
        let checksum = Checksum(.sha256, sha256)
        if let cached = try? Data(contentsOf: file), (try? checksum.verify(cached, name: file.path)) != nil {
            return cached
        }
        let data = try await http.data(from: url)
        try checksum.verify(data, name: url.lastPathComponent)
        try FileSystem.writeAtomically(data, to: file)
        return data
    }

    private static func readOffline(_ file: URL) throws -> Data {
        guard let data = try? Data(contentsOf: file) else {
            throw LauncherError.metadataMissingOffline(file.path)
        }
        return data
    }

    private func serverURL(_ relativePath: String) -> URL {
        settings.current.effectiveMetadataBaseURL(configuration).appending(path: relativePath)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data, file: URL) throws -> Value {
        try JSONFiles.decode(type, from: data, name: file.path)
    }

    private func checkFormatVersion(_ version: Int, file: URL) throws {
        guard Self.acceptedFormatVersions.contains(version) else {
            throw LauncherError.unsupportedFormatVersion(file: file.path, version: version)
        }
    }
}
