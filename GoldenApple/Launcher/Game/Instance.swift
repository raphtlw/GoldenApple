import Foundation

/// A game instance as the app shows it. Built from `Instance.json` and `Components.json`.
nonisolated struct Instance: Hashable, Identifiable, Sendable {
    /// The folder name below `Instances/`.
    let id: String
    let name: String
    let folder: URL
    /// The `Minecraft/` game directory.
    let gameFolder: URL
    let minecraftVersion: String
    let loader: ModLoader?
    let loaderVersion: String?
    let lastPlayed: Date?

    var paths: InstancePaths {
        InstancePaths(folder: folder)
    }
}

/// The contents of `Instance.json`. Keys missing from the file decode to the defaults.
nonisolated struct InstanceConfiguration: Codable, Sendable {
    var name: String
    var lastPlayed: Date?
    /// Extra environment variables for the game process.
    var environment: [String: String] = [:]
    /// The last Java check, reused while the binary's signature is unchanged.
    var javaCheck: JavaCheckRecord?

    init(name: String) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name, lastPlayed, environment, javaCheck
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lastPlayed = try container.decodeIfPresent(Date.self, forKey: .lastPlayed)
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        javaCheck = try container.decodeIfPresent(JavaCheckRecord.self, forKey: .javaCheck)
    }
}
