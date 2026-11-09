import Foundation

/// Package identifiers on the metadata server.
nonisolated enum ComponentID {
    static let minecraft = "net.minecraft"
    static let lwjgl2 = "org.lwjgl"
    static let lwjgl3 = "org.lwjgl3"
    static let fabricLoader = "net.fabricmc.fabric-loader"
    static let fabricIntermediary = "net.fabricmc.intermediary"
    static let quiltLoader = "org.quiltmc.quilt-loader"
    static let quiltHashed = "org.quiltmc.hashed"
    static let forge = "net.minecraftforge"
    static let neoForge = "net.neoforged"
    static let mojangJava = "net.minecraft.java"
    static let azulJava = "com.azul.java"
    static let adoptiumJava = "net.adoptium.java"

    /// Mapping packages whose versions are named after the Minecraft version.
    static let mappingsNamedAfterMinecraft: Set<String> = [fabricIntermediary, quiltHashed]

    static func displayName(_ uid: String) -> String {
        if let loader = ModLoader(uid: uid) {
            return loader.displayName
        }
        return switch uid {
        case minecraft: "Minecraft"
        case lwjgl2: "LWJGL 2"
        case lwjgl3: "LWJGL 3"
        case fabricIntermediary: "Intermediary Mappings"
        case quiltHashed: "Hashed Mappings"
        default: uid
        }
    }
}

/// The mod loaders a player can pick for an instance.
nonisolated enum ModLoader: String, Codable, CaseIterable, Sendable {
    case fabric
    case quilt
    case forge
    case neoForge

    init?(uid: String) {
        guard let loader = Self.allCases.first(where: { $0.uid == uid }) else {
            return nil
        }
        self = loader
    }

    var uid: String {
        switch self {
        case .fabric: ComponentID.fabricLoader
        case .quilt: ComponentID.quiltLoader
        case .forge: ComponentID.forge
        case .neoForge: ComponentID.neoForge
        }
    }

    var displayName: String {
        switch self {
        case .fabric: "Fabric"
        case .quilt: "Quilt"
        case .forge: "Forge"
        case .neoForge: "NeoForge"
        }
    }

    /// Forge and NeoForge builds exist for one Minecraft version each. Fabric and Quilt work with any.
    var isBuiltPerMinecraftVersion: Bool {
        self == .forge || self == .neoForge
    }
}
