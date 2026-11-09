import Foundation

/// The launcher's internal services, built once per launcher and shared by all areas.
nonisolated struct LauncherServices: Sendable {
    let configuration: GoldenAppleConfiguration
    let paths: LauncherPaths
    let settings: SettingsStore
    let http: HTTPClient
    let httpCache: HTTPCache
    let downloads: DownloadQueue
    let metadata: MetadataClient
    let catalog: VersionCatalog
    let resolver: ComponentResolver
    let libraries: LibraryLocator
    let assets: AssetInstaller
    let instances: InstanceStore
    let javaDiscovery: JavaDiscovery
    let javaInstaller: JavaRuntimeInstaller
    let javaSelector: JavaSelector
    let accounts: AccountService
    let runningGames: RunningGames
    let modrinth: ModrinthClient
    let curseForge: CurseForgeClient
    let installedContent: InstalledContentStore

    init(configuration: GoldenAppleConfiguration, paths: LauncherPaths) {
        self.configuration = configuration
        self.paths = paths
        settings = SettingsStore(file: paths.settingsFile)
        http = HTTPClient(userAgent: configuration.userAgent)
        httpCache = HTTPCache(http: http, storeFile: paths.httpCacheFile)
        downloads = DownloadQueue(http: http, stagingFolder: paths.downloads, settings: settings)
        metadata = MetadataClient(paths: paths, configuration: configuration, settings: settings, http: http, httpCache: httpCache)
        catalog = VersionCatalog(metadata: metadata)
        resolver = ComponentResolver(metadata: metadata, catalog: catalog)
        libraries = LibraryLocator(paths: paths, libraryBaseURL: configuration.libraryBaseURL)
        assets = AssetInstaller(paths: paths, resourceBaseURL: configuration.resourceBaseURL, downloads: downloads)
        instances = InstanceStore(paths: paths)
        javaDiscovery = JavaDiscovery(paths: paths)
        javaInstaller = JavaRuntimeInstaller(paths: paths, http: http, downloads: downloads)
        javaSelector = JavaSelector(
            paths: paths,
            settings: settings,
            metadata: metadata,
            installer: javaInstaller,
            discovery: javaDiscovery,
            instances: instances
        )
        accounts = AccountService(file: paths.accountsFile, http: http, configuration: configuration, settings: settings)
        runningGames = RunningGames()
        modrinth = ModrinthClient(http: http)
        curseForge = CurseForgeClient(http: http, settings: settings, configuration: configuration)
        installedContent = InstalledContentStore()
    }

    func contentSource(_ provider: ContentProvider) -> any ContentSource {
        switch provider {
        case .modrinth: modrinth
        case .curseForge: curseForge
        }
    }

    /// The merged launch profile of an instance's enabled components.
    func profile(for instance: Instance, mode: MetadataMode) async throws -> LaunchProfile {
        try await resolver.profile(for: instances.components(of: instance), metadataMode: mode)
    }
}
