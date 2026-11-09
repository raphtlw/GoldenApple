import Foundation

/// The Modrinth API v2. It needs no key.
nonisolated struct ModrinthClient: ContentSource {
    static let essentialProjectID = "k2ZPuTBm"
    private static let baseURL = URL(string: "https://api.modrinth.com/v2/")!
    private static let websiteURL = URL(string: "https://modrinth.com/")!
    private static let serviceName = "Modrinth"
    private static let maximumPageSize = 100

    let http: HTTPClient

    /// Searches by relevance. The loader facet is used only for mods.
    func search(_ query: String, kind: ContentKind, target: ContentTarget?, offset: Int, limit: Int) async throws -> ContentSearchPage {
        var facets = [["project_type:\(kind.modrinthProjectType)"]]
        if let target {
            facets.append(["versions:\(target.minecraftVersion)"])
            if kind.searchFiltersByLoader, !target.loaders.isEmpty {
                facets.append(target.loaders.map { "categories:\($0.modrinthName)" })
            }
        }
        let response = try await get(ModrinthSearchResponse.self, "search", query: [
            ("query", query),
            ("facets", try Self.jsonText(facets)),
            ("offset", String(max(0, offset))),
            ("limit", String(min(max(1, limit), Self.maximumPageSize))),
            ("index", "relevance"),
        ])
        let projects = response.hits.map { hit in
            makeProject(
                id: hit.projectId,
                slug: hit.slug,
                title: hit.title,
                summary: hit.description,
                author: hit.author ?? "",
                downloads: hit.downloads,
                iconURL: hit.iconUrl,
                projectType: hit.projectType,
                fallbackKind: kind
            )
        }
        return ContentSearchPage(projects: projects, totalCount: response.totalHits)
    }

    /// Accepts a project ID or slug.
    func project(_ id: String) async throws -> ContentProject {
        let project = try await get(ModrinthProject.self, "project/\(id)")
        return makeProject(
            id: project.id,
            slug: project.slug,
            title: project.title,
            summary: project.description,
            author: "",
            downloads: project.downloads,
            iconURL: project.iconUrl,
            projectType: project.projectType,
            fallbackKind: .mod
        )
    }

    /// Filters by Minecraft version, and by loader for mods and modpacks.
    func versions(of project: ContentProject, target: ContentTarget?) async throws -> [ContentVersion] {
        var query = [("include_changelog", "false")]
        if let target {
            query.append(("game_versions", try Self.jsonText([target.minecraftVersion])))
            if project.kind.versionsFilterByLoader, !target.loaders.isEmpty {
                query.append(("loaders", try Self.jsonText(target.loaders.map(\.modrinthName))))
            }
        }
        return try await get([ModrinthVersion].self, "project/\(project.projectID)/version", query: query).map(\.contentVersion)
    }

    func version(_ id: String, projectID: String?) async throws -> ContentVersion {
        try await get(ModrinthVersion.self, "version/\(id)").contentVersion
    }

    // MARK: Helpers

    private func get<Value: Decodable>(_ type: Value.Type, _ path: String, query: [(String, String)] = []) async throws -> Value {
        let url = FormEncoding.url(Self.baseURL.appending(path: path), query: query)
        let data = try await http.data(for: .jsonGet(url))
        return try ServiceResponse.decode(type, from: data, service: Self.serviceName, keys: .convertFromSnakeCase)
    }

    private func makeProject(
        id: String,
        slug: String,
        title: String,
        summary: String,
        author: String,
        downloads: Int,
        iconURL: URL?,
        projectType: String,
        fallbackKind: ContentKind
    ) -> ContentProject {
        ContentProject(
            provider: .modrinth,
            projectID: id,
            slug: slug,
            title: title,
            summary: summary,
            author: author,
            downloads: downloads,
            iconURL: iconURL,
            pageURL: Self.websiteURL.appending(path: projectType).appending(path: slug),
            kind: ContentKind(modrinthProjectType: projectType) ?? fallbackKind
        )
    }

    private static func jsonText(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

// MARK: API models

nonisolated private struct ModrinthSearchResponse: Decodable {
    let hits: [ModrinthSearchHit]
    let totalHits: Int
}

nonisolated private struct ModrinthSearchHit: Decodable {
    let projectId: String
    let slug: String
    let title: String
    let description: String
    let author: String?
    let downloads: Int
    let iconUrl: URL?
    let projectType: String
}

nonisolated private struct ModrinthProject: Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let downloads: Int
    let iconUrl: URL?
    let projectType: String
}

nonisolated private struct ModrinthVersion: Decodable {
    struct Dependency: Decodable {
        let versionId: String?
        let projectId: String?
        let dependencyType: String
    }

    struct File: Decodable {
        let url: URL
        let filename: String
        let primary: Bool
        let size: Int64?
        let hashes: [String: String]
    }

    let id: String
    let projectId: String
    let name: String
    let versionNumber: String
    let versionType: String
    let datePublished: Date
    let gameVersions: [String]
    let loaders: [String]
    let dependencies: [Dependency]
    let files: [File]

    var contentVersion: ContentVersion {
        let file = files.first(where: \.primary) ?? files.first
        return ContentVersion(
            provider: .modrinth,
            id: id,
            projectID: projectId,
            name: name,
            versionNumber: versionNumber,
            releaseType: ContentReleaseType(rawValue: versionType) ?? .alpha,
            published: datePublished,
            gameVersions: gameVersions,
            loaders: loaders,
            file: file.map { file in
                ContentFile(
                    fileName: file.filename,
                    downloadURL: file.url,
                    size: file.size,
                    sha1: file.hashes["sha1"],
                    sha512: file.hashes["sha512"]
                )
            },
            dependencies: dependencies.map { dependency in
                ContentDependency(projectID: dependency.projectId, versionID: dependency.versionId, kind: Self.dependencyKind(dependency.dependencyType))
            }
        )
    }

    private static func dependencyKind(_ type: String) -> ContentDependency.Kind {
        switch type {
        case "required": .required
        case "optional": .optional
        case "incompatible": .incompatible
        case "embedded": .embedded
        default: .other
        }
    }
}
