import Foundation
import os

/// The launcher entry point the app uses. Other areas add their members in extensions in other files
/// and reach the shared services through `services`.
actor GoldenAppleLauncher {
    nonisolated let configuration: GoldenAppleConfiguration
    nonisolated let paths: LauncherPaths
    nonisolated let services: LauncherServices

    /// `dataRoot` replaces `~/Library/Application Support/GoldenApple`, for example in tests.
    init(configuration: GoldenAppleConfiguration = .default, dataRoot: URL? = nil) {
        let paths = dataRoot.map(LauncherPaths.init(root:)) ?? LauncherPaths(configuration: configuration)
        self.configuration = configuration
        self.paths = paths
        services = LauncherServices(configuration: configuration, paths: paths)
    }

    /// Creates the data folders, empties `Cache/Downloads`, and loads the settings and accounts.
    func prepare() async throws {
        for folder in paths.requiredFolders {
            try FileSystem.createFolder(folder)
        }
        try FileSystem.emptyFolder(paths.downloads)
        try services.settings.load()
        try services.accounts.load()
        LauncherLog.general.info("Prepared data folder \(self.paths.root.path, privacy: .public)")
    }

    // MARK: Settings

    func settings() -> LauncherSettings {
        services.settings.current
    }

    func updateSettings(_ change: @Sendable (inout LauncherSettings) -> Void) throws {
        try services.settings.update(change)
    }

    /// The client ID from settings when set, else the build-time value.
    func microsoftClientID() -> String {
        services.settings.current.effectiveMicrosoftClientID(configuration)
    }

    // MARK: Versions

    func minecraftVersions(includeSnapshots: Bool) async throws -> [GameVersion] {
        try await services.catalog.minecraftVersions(includeSnapshots: includeSnapshots)
    }

    func loaderVersions(_ loader: ModLoader, minecraftVersion: String) async throws -> [LoaderVersion] {
        try await services.catalog.loaderVersions(loader, minecraftVersion: minecraftVersion)
    }

    // MARK: Instances

    func instances() throws -> [Instance] {
        try services.instances.list()
    }

    /// Creates an instance. Without `loaderVersion`, the recommended loader version is used.
    func createInstance(name: String, minecraftVersion: String, loader: ModLoader?, loaderVersion: String?) async throws -> Instance {
        try await services.catalog.supportedMinecraftDocument(minecraftVersion)
        var components = [InstanceComponent.pinned(ComponentID.minecraft, version: minecraftVersion)]
        if let loader {
            let version = try await resolvedLoaderVersion(loader, requested: loaderVersion, minecraftVersion: minecraftVersion)
            components.append(.pinned(loader.uid, version: version))
        }
        let resolved = try await services.resolver.resolve(components)
        return try services.instances.create(name: name, components: resolved)
    }

    /// Changes Minecraft and moves the loader to its recommended version for the new Minecraft version.
    func setMinecraftVersion(_ version: String, for instance: Instance) async throws {
        try await services.catalog.supportedMinecraftDocument(version)
        let components = try services.instances.components(of: instance)
        let resolved = try await services.resolver.changeMinecraftVersion(of: components, to: version)
        try services.instances.saveComponents(resolved, for: instance)
    }

    /// Replaces the mod loader, or removes it when `loader` is nil.
    func setLoader(_ loader: ModLoader?, version: String?, for instance: Instance) async throws {
        var components = try services.instances.components(of: instance)
        components.removeAll { ModLoader(uid: $0.uid) != nil }
        if let loader {
            guard let minecraftVersion = components.minecraftVersion else {
                throw LauncherError.missingMinecraftComponent(instance.name)
            }
            let loaderVersion = try await resolvedLoaderVersion(loader, requested: version, minecraftVersion: minecraftVersion)
            components.append(.pinned(loader.uid, version: loaderVersion))
        }
        let resolved = try await services.resolver.resolve(components)
        try services.instances.saveComponents(resolved, for: instance)
    }

    func renameInstance(_ instance: Instance, to name: String) throws -> Instance {
        try services.instances.rename(instance, to: name)
    }

    /// Moves the instance folder to the Trash.
    func deleteInstance(_ instance: Instance) throws {
        try services.instances.delete(instance)
    }

    func components(of instance: Instance) throws -> [InstanceComponent] {
        try services.instances.components(of: instance)
    }

    // MARK: Java

    func javaInstallations() async -> [JavaInstallation] {
        await services.javaDiscovery.installations()
    }

    // MARK: Helpers

    private func resolvedLoaderVersion(_ loader: ModLoader, requested: String?, minecraftVersion: String) async throws -> String {
        if let requested = requested.nonEmpty {
            return requested
        }
        return try await services.catalog.recommendedLoaderVersion(loader, minecraftVersion: minecraftVersion)
    }
}
