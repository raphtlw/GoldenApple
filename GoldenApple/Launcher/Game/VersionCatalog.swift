import Foundation

nonisolated struct GameVersion: Hashable, Identifiable, Sendable {
    let id: String
    /// `release` or `snapshot`.
    let type: String
    let releaseTime: Date
}

nonisolated struct LoaderVersion: Hashable, Identifiable, Sendable {
    let version: String
    let isRecommended: Bool
    let releaseTime: Date

    var id: String { version }
}

/// Minecraft and loader version lists for players, and the rules for which Minecraft versions GoldenApple supports.
nonisolated struct VersionCatalog: Sendable {
    /// The oldest Minecraft version GoldenApple can launch.
    static let oldestSupportedMinecraft = "1.6.1"
    private static let unsupportedTraits: Set<String> = ["legacyLaunch", "alphaLaunch"]

    let metadata: MetadataClient

    /// Supported Minecraft versions, newest first.
    func minecraftVersions(includeSnapshots: Bool, mode: MetadataMode = .online) async throws -> [GameVersion] {
        let shownTypes: Set<String> = includeSnapshots ? ["release", "snapshot"] : ["release"]
        let list = try await metadata.versionList(ComponentID.minecraft, mode: mode)
        return Self.supportedEntries(of: list)
            .filter { shownTypes.contains($0.type ?? "") }
            .sorted { $0.releaseTime > $1.releaseTime }
            .map { GameVersion(id: $0.version, type: $0.type ?? "", releaseTime: $0.releaseTime) }
    }

    /// Loader versions, newest first. Forge and NeoForge only list builds for `minecraftVersion`.
    func loaderVersions(_ loader: ModLoader, minecraftVersion: String, mode: MetadataMode = .online) async throws -> [LoaderVersion] {
        let list = try await metadata.versionList(loader.uid, mode: mode)
        return list.versions
            .filter { !loader.isBuiltPerMinecraftVersion || Self.requiresMinecraft(minecraftVersion, $0) }
            .sorted { $0.releaseTime > $1.releaseTime }
            .map { LoaderVersion(version: $0.version, isRecommended: $0.isRecommended, releaseTime: $0.releaseTime) }
    }

    /// The first recommended loader version, else the newest.
    func recommendedLoaderVersion(_ loader: ModLoader, minecraftVersion: String, mode: MetadataMode = .online) async throws -> String {
        let versions = try await loaderVersions(loader, minecraftVersion: minecraftVersion, mode: mode)
        guard let version = versions.first(where: \.isRecommended) ?? versions.first else {
            throw LauncherError.noLoaderVersion(loader: loader.displayName, minecraftVersion: minecraftVersion)
        }
        return version.version
    }

    /// The newest `release` version of a package, else its newest version of any type.
    func newestRelease(of uid: String, mode: MetadataMode) async throws -> String {
        let versions = try await metadata.versionList(uid, mode: mode).versions.sorted { $0.releaseTime > $1.releaseTime }
        guard let newest = versions.first(where: { $0.type == "release" }) ?? versions.first else {
            throw LauncherError.unknownPackage(uid)
        }
        return newest.version
    }

    /// Loads the Minecraft version document and refuses versions GoldenApple cannot launch.
    @discardableResult
    func supportedMinecraftDocument(_ version: String, mode: MetadataMode = .online) async throws -> VersionDocument {
        let document = try await metadata.versionDocument(ComponentID.minecraft, version: version, mode: mode)
        guard Self.isLaunchable(document) else {
            throw LauncherError.unsupportedMinecraftVersion(version)
        }
        return document
    }

    /// Entries released at or after the oldest supported version in the same list.
    static func supportedEntries(of list: VersionList) -> [VersionListEntry] {
        guard let oldest = list.versions.first(where: { $0.version == oldestSupportedMinecraft }) else {
            return list.versions
        }
        return list.versions.filter { $0.releaseTime >= oldest.releaseTime }
    }

    static func isLaunchable(_ document: VersionDocument) -> Bool {
        document.mainClass.nonEmpty != nil && unsupportedTraits.isDisjoint(with: document.traits)
    }

    private static func requiresMinecraft(_ minecraftVersion: String, _ entry: VersionListEntry) -> Bool {
        entry.requires.contains { $0.uid == ComponentID.minecraft && $0.equals == minecraftVersion }
    }
}
