import Foundation

/// What the installer needs from a content provider. Modrinth and CurseForge implement it.
nonisolated protocol ContentSource: Sendable {
    func search(_ query: String, kind: ContentKind, target: ContentTarget?, offset: Int, limit: Int) async throws -> ContentSearchPage
    func project(_ id: String) async throws -> ContentProject
    /// Versions for the target, or every version when `target` is nil.
    func versions(of project: ContentProject, target: ContentTarget?) async throws -> [ContentVersion]
    /// One version. CurseForge looks a file up faster when its project is known.
    func version(_ id: String, projectID: String?) async throws -> ContentVersion
}

nonisolated extension ContentSource {
    /// The best version of the project for the target, see `ContentVersion.best(of:)`.
    func bestVersion(of project: ContentProject, target: ContentTarget?) async throws -> ContentVersion {
        guard let version = ContentVersion.best(of: try await versions(of: project, target: target)) else {
            throw LauncherError.noCompatibleContentVersion(title: project.title, target: target?.displayName ?? "any Minecraft version")
        }
        return version
    }
}
