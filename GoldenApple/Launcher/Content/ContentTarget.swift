import Foundation

/// The Minecraft version and the mod loaders whose content an instance accepts.
/// A Quilt instance also accepts Fabric content. A NeoForge instance on Minecraft 1.20.1 also accepts Forge content.
nonisolated struct ContentTarget: Hashable, Sendable {
    let minecraftVersion: String
    /// The instance loader first, then the loaders it is compatible with. Empty without a loader.
    let loaders: [ModLoader]

    init(minecraftVersion: String, loader: ModLoader?) {
        self.minecraftVersion = minecraftVersion
        switch loader {
        case .quilt:
            loaders = [.quilt, .fabric]
        case .neoForge where minecraftVersion == "1.20.1":
            loaders = [.neoForge, .forge]
        case let loader?:
            loaders = [loader]
        case nil:
            loaders = []
        }
    }

    init(_ instance: Instance) {
        self.init(minecraftVersion: instance.minecraftVersion, loader: instance.loader)
    }

    var displayName: String {
        let loaderName = loaders.first.map { " with \($0.displayName)" } ?? ""
        return "Minecraft \(minecraftVersion)\(loaderName)"
    }
}

nonisolated extension ModLoader {
    /// The loader name in Modrinth versions and search categories.
    var modrinthName: String {
        switch self {
        case .fabric: "fabric"
        case .quilt: "quilt"
        case .forge: "forge"
        case .neoForge: "neoforge"
        }
    }

    /// The CurseForge `ModLoaderType` value.
    var curseForgeLoaderType: Int {
        switch self {
        case .forge: 1
        case .fabric: 4
        case .quilt: 5
        case .neoForge: 6
        }
    }

    /// Matches loader names such as `Fabric` or `neoforge`, as Modrinth and CurseForge write them.
    init?(providerName: String) {
        let name = providerName.lowercased()
        guard let loader = Self.allCases.first(where: { $0.modrinthName == name }) else {
            return nil
        }
        self = loader
    }
}
