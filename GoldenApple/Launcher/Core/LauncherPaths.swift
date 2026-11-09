import Foundation

/// Every location in the launcher data folder.
nonisolated struct LauncherPaths: Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    init(configuration: GoldenAppleConfiguration) {
        self.init(root: URL.applicationSupportDirectory.appending(path: configuration.dataDirectoryName, directoryHint: .isDirectory))
    }

    // MARK: Top level

    var instances: URL { folder("Instances") }
    var versions: URL { folder("Versions") }
    var libraries: URL { folder("Libraries") }
    var assets: URL { folder("Assets") }
    var java: URL { folder("Java") }
    var cache: URL { folder("Cache") }
    var accountsFile: URL { root.appending(path: "Accounts.json") }
    var settingsFile: URL { root.appending(path: "Settings.json") }

    /// Folders that `prepare()` creates.
    var requiredFolders: [URL] {
        [instances, versions, libraries, assets, java, cache, downloads, javaArchives]
    }

    // MARK: Cache

    var downloads: URL { cache.appending(path: "Downloads", directoryHint: .isDirectory) }
    var javaArchives: URL { cache.appending(path: "Java Archives", directoryHint: .isDirectory) }
    var httpCacheFile: URL { cache.appending(path: "HTTP Cache.json") }

    // MARK: Metadata

    var packageIndexFile: URL { versions.appending(path: "index.json") }

    func packageFolder(_ uid: String) -> URL {
        versions.appending(path: uid, directoryHint: .isDirectory)
    }

    func versionListFile(_ uid: String) -> URL {
        packageFolder(uid).appending(path: "index.json")
    }

    func versionFolder(uid: String, version: String) -> URL {
        packageFolder(uid).appending(path: FileSystem.versionFolderName(version), directoryHint: .isDirectory)
    }

    func versionDocumentFile(uid: String, version: String) -> URL {
        versionFolder(uid: uid, version: version).appending(path: "version.json")
    }

    func clientJar(minecraftVersion: String) -> URL {
        versionFolder(uid: ComponentID.minecraft, version: minecraftVersion).appending(path: "client.jar")
    }

    // MARK: Assets

    var assetIndexes: URL { assets.appending(path: "indexes", directoryHint: .isDirectory) }
    var assetObjects: URL { assets.appending(path: "objects", directoryHint: .isDirectory) }

    func assetIndexFile(id: String) -> URL {
        assetIndexes.appending(path: "\(id).json")
    }

    func assetObject(hash: String) -> URL {
        assetObjects.appending(path: String(hash.prefix(2)), directoryHint: .isDirectory).appending(path: hash)
    }

    func virtualAssets(id: String) -> URL {
        assets.appending(path: "virtual", directoryHint: .isDirectory).appending(path: id, directoryHint: .isDirectory)
    }

    // MARK: Java

    func javaRuntime(_ name: String) -> URL {
        java.appending(path: name, directoryHint: .isDirectory)
    }

    // MARK: Instances

    func instance(_ id: String) -> InstancePaths {
        InstancePaths(folder: instances.appending(path: id, directoryHint: .isDirectory))
    }

    private func folder(_ name: String) -> URL {
        root.appending(path: name, directoryHint: .isDirectory)
    }
}

/// Files and folders inside one instance folder.
nonisolated struct InstancePaths: Sendable {
    let folder: URL

    var configurationFile: URL { folder.appending(path: "Instance.json") }
    var componentsFile: URL { folder.appending(path: "Components.json") }
    var installedContentFile: URL { folder.appending(path: "Installed Content.json") }
    var natives: URL { folder.appending(path: "Natives", directoryHint: .isDirectory) }
    var gameFolder: URL { folder.appending(path: "Minecraft", directoryHint: .isDirectory) }
    var logs: URL { folder.appending(path: "Logs", directoryHint: .isDirectory) }

    func logFile(_ kind: LaunchLogKind) -> URL {
        logs.appending(path: kind.fileName)
    }
}
