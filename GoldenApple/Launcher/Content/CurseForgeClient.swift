import Foundation

/// The CurseForge API v1. Every call needs the API key from settings or the configuration.
nonisolated struct CurseForgeClient: ContentSource {
    private static let baseURL = URL(string: "https://api.curseforge.com/v1/")!
    private static let serviceName = "CurseForge"
    private static let minecraftGameID = "432"
    private static let popularitySortField = "2"
    /// The largest page the API returns.
    private static let maximumPageSize = 50
    /// `index + pageSize` may not exceed this.
    private static let maximumResultWindow = 10_000

    let http: HTTPClient
    let settings: SettingsStore
    let configuration: GoldenAppleConfiguration

    /// Sorted by popularity. The loader filter is used only for mods.
    func search(_ query: String, kind: ContentKind, target: ContentTarget?, offset: Int, limit: Int) async throws -> ContentSearchPage {
        let index = min(max(0, offset), Self.maximumResultWindow - 1)
        let pageSize = min(max(1, limit), Self.maximumPageSize, Self.maximumResultWindow - index)
        var parameters = [
            ("gameId", Self.minecraftGameID),
            ("classId", String(kind.curseForgeClassID)),
            ("searchFilter", query),
        ]
        if let target {
            parameters.append(("gameVersion", target.minecraftVersion))
            if kind.searchFiltersByLoader, !target.loaders.isEmpty {
                parameters.append(("modLoaderTypes", Self.listText(target.loaders.map(\.curseForgeLoaderType))))
            }
        }
        parameters += [
            ("index", String(index)),
            ("pageSize", String(pageSize)),
            ("sortField", Self.popularitySortField),
            ("sortOrder", "desc"),
        ]
        let response = try await get(CurseForgePage<CurseForgeMod>.self, "mods/search", query: parameters)
        return ContentSearchPage(
            projects: response.data.map { $0.contentProject(fallbackKind: kind) },
            totalCount: response.pagination?.totalCount ?? response.data.count
        )
    }

    func project(_ id: String) async throws -> ContentProject {
        try await get(CurseForgeData<CurseForgeMod>.self, "mods/\(id)").data.contentProject(fallbackKind: .mod)
    }

    /// Several projects in one request. Projects the API does not know are left out.
    func projects(_ ids: [Int]) async throws -> [ContentProject] {
        try await mods(ids).map { $0.contentProject(fallbackKind: .mod) }
    }

    /// Like `projects(_:)`, with the API fields such as the class ID.
    func mods(_ ids: [Int]) async throws -> [CurseForgeMod] {
        guard !ids.isEmpty else {
            return []
        }
        return try await post([CurseForgeMod].self, "mods", body: ["modIds": ids])
    }

    /// Filters by Minecraft version, and by loader for mods and modpacks. A target with several loaders
    /// needs one request per loader, because the files endpoint takes one loader type.
    func versions(of project: ContentProject, target: ContentTarget?) async throws -> [ContentVersion] {
        var filters: [[(String, String)]] = [[]]
        if let target {
            let gameVersion = ("gameVersion", target.minecraftVersion)
            if project.kind.versionsFilterByLoader, !target.loaders.isEmpty {
                filters = target.loaders.map { [gameVersion, ("modLoaderType", String($0.curseForgeLoaderType))] }
            } else {
                filters = [[gameVersion]]
            }
        }
        var files: [CurseForgeFile] = []
        for filter in filters {
            for file in try await allFiles(of: project.projectID, filter: filter) where !files.contains(where: { $0.id == file.id }) {
                files.append(file)
            }
        }
        return files.map(\.contentVersion)
    }

    func version(_ id: String, projectID: String?) async throws -> ContentVersion {
        if let projectID {
            return try await file(id, of: projectID)
        }
        guard let fileID = Int(id), let version = try await files([fileID]).first else {
            throw LauncherError.unexpectedResponse(service: Self.serviceName, reason: "file \(id) does not exist")
        }
        return version
    }

    func file(_ fileID: String, of projectID: String) async throws -> ContentVersion {
        try await get(CurseForgeData<CurseForgeFile>.self, "mods/\(projectID)/files/\(fileID)").data.contentVersion
    }

    /// Several files in one request. Files the API does not know are left out.
    func files(_ ids: [Int]) async throws -> [ContentVersion] {
        guard !ids.isEmpty else {
            return []
        }
        return try await post([CurseForgeFile].self, "mods/files", body: ["fileIds": ids]).map(\.contentVersion)
    }

    /// The page where a player downloads a file that launchers may not download.
    static func downloadPage(projectPage: URL?, fileID: String) -> URL? {
        projectPage?.appending(path: "download").appending(path: fileID)
    }

    // MARK: Requests

    /// Reads every page of the file list.
    private func allFiles(of projectID: String, filter: [(String, String)]) async throws -> [CurseForgeFile] {
        var files: [CurseForgeFile] = []
        while files.count < Self.maximumResultWindow {
            let pageSize = min(Self.maximumPageSize, Self.maximumResultWindow - files.count)
            let query = filter + [("index", String(files.count)), ("pageSize", String(pageSize))]
            let page = try await get(CurseForgePage<CurseForgeFile>.self, "mods/\(projectID)/files", query: query)
            files += page.data
            let totalCount = page.pagination?.totalCount ?? files.count
            if page.data.isEmpty || files.count >= totalCount {
                break
            }
        }
        return files
    }

    private func get<Value: Decodable>(_ type: Value.Type, _ path: String, query: [(String, String)] = []) async throws -> Value {
        let request = URLRequest.jsonGet(FormEncoding.url(Self.baseURL.appending(path: path), query: query))
        return try await send(request, decoding: type)
    }

    /// POST with a JSON body. The answer's `data` is returned.
    private func post<Value: Decodable>(_ type: Value.Type, _ path: String, body: [String: [Int]]) async throws -> Value {
        let request = try URLRequest.jsonPost(Self.baseURL.appending(path: path), body: body)
        return try await send(request, decoding: CurseForgeData<Value>.self).data
    }

    private func send<Value: Decodable>(_ request: URLRequest, decoding type: Value.Type) async throws -> Value {
        var request = request
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        let data = try await http.data(for: request)
        return try ServiceResponse.decode(type, from: data, service: Self.serviceName)
    }

    /// Fails before any network access when no key is set.
    private func apiKey() throws -> String {
        let key = settings.current.effectiveCurseForgeAPIKey(configuration).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw LauncherError.missingCurseForgeAPIKey
        }
        return key
    }

    private static func listText(_ values: [Int]) -> String {
        "[" + values.map(String.init).joined(separator: ",") + "]"
    }
}

// MARK: API models

nonisolated struct CurseForgeData<Value: Decodable>: Decodable {
    let data: Value
}

nonisolated struct CurseForgePage<Value: Decodable>: Decodable {
    struct Pagination: Decodable {
        let totalCount: Int
    }

    let data: [Value]
    let pagination: Pagination?
}

nonisolated struct CurseForgeMod: Decodable {
    struct Links: Decodable {
        let websiteUrl: URL?
    }

    struct Author: Decodable {
        let name: String
    }

    struct Logo: Decodable {
        let thumbnailUrl: URL?
    }

    let id: Int
    let slug: String
    let name: String
    let summary: String?
    let authors: [Author]?
    /// The API documents an integer. Decoding a `Double` also accepts a value written with a fraction or exponent.
    let downloadCount: Double?
    let logo: Logo?
    let links: Links?
    let classId: Int?

    func contentProject(fallbackKind: ContentKind) -> ContentProject {
        ContentProject(
            provider: .curseForge,
            projectID: String(id),
            slug: slug,
            title: name,
            summary: summary ?? "",
            author: authors?.first?.name ?? "",
            downloads: Int(downloadCount ?? 0),
            iconURL: logo?.thumbnailUrl,
            pageURL: links?.websiteUrl,
            kind: classId.flatMap(ContentKind.init(curseForgeClassID:)) ?? fallbackKind
        )
    }
}

nonisolated struct CurseForgeFile: Decodable {
    struct Hash: Decodable {
        let value: String
        let algo: Int
    }

    struct Dependency: Decodable {
        let modId: Int
        let relationType: Int
    }

    private static let sha1Algorithm = 1

    let id: Int
    let modId: Int
    let displayName: String
    let fileName: String
    let fileDate: Date
    let releaseType: Int
    let downloadUrl: URL?
    let fileLength: Int64?
    let gameVersions: [String]
    let hashes: [Hash]
    let dependencies: [Dependency]

    var contentVersion: ContentVersion {
        ContentVersion(
            provider: .curseForge,
            id: String(id),
            projectID: String(modId),
            name: displayName,
            versionNumber: displayName,
            releaseType: Self.releaseType(releaseType),
            published: fileDate,
            gameVersions: gameVersions.filter { $0.first?.isNumber == true },
            loaders: gameVersions.compactMap { ModLoader(providerName: $0)?.modrinthName },
            file: ContentFile(
                fileName: fileName,
                downloadURL: downloadUrl,
                size: fileLength,
                sha1: hashes.first { $0.algo == Self.sha1Algorithm }?.value,
                sha512: nil
            ),
            dependencies: dependencies.map { dependency in
                ContentDependency(projectID: String(dependency.modId), versionID: nil, kind: Self.dependencyKind(dependency.relationType))
            }
        )
    }

    private static func releaseType(_ value: Int) -> ContentReleaseType {
        switch value {
        case 1: .release
        case 2: .beta
        default: .alpha
        }
    }

    private static func dependencyKind(_ relationType: Int) -> ContentDependency.Kind {
        switch relationType {
        case 1: .embedded
        case 2: .optional
        case 3: .required
        case 5: .incompatible
        default: .other
        }
    }
}
