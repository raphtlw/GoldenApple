import Foundation

/// One entry of `Components.json`: a package and the version an instance uses.
nonisolated struct InstanceComponent: Codable, Hashable, Identifiable, Sendable {
    var uid: String
    var version: String
    /// Added automatically because another component requires it.
    var isDependency: Bool
    /// Picked by the player. Minecraft is always pinned.
    var isPinned: Bool
    var isEnabled: Bool

    var id: String { uid }
    var name: String { ComponentID.displayName(uid) }

    init(uid: String, version: String, isDependency: Bool = false, isPinned: Bool = false, isEnabled: Bool = true) {
        self.uid = uid
        self.version = version
        self.isDependency = isDependency
        self.isPinned = isPinned
        self.isEnabled = isEnabled
    }

    static func pinned(_ uid: String, version: String) -> InstanceComponent {
        InstanceComponent(uid: uid, version: version, isPinned: true)
    }

    static func dependency(_ uid: String, version: String) -> InstanceComponent {
        InstanceComponent(uid: uid, version: version, isDependency: true)
    }

    private enum CodingKeys: String, CodingKey {
        case uid, version, isDependency, isPinned, isEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        version = try container.decode(String.self, forKey: .version)
        isDependency = try container.decodeIfPresent(Bool.self, forKey: .isDependency) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// The contents of `Components.json`.
nonisolated struct ComponentList: Codable, Sendable {
    var components: [InstanceComponent]
}

nonisolated extension Array where Element == InstanceComponent {
    func component(_ uid: String) -> InstanceComponent? {
        first { $0.uid == uid }
    }

    var minecraftVersion: String? {
        component(ComponentID.minecraft)?.version
    }

    /// The first enabled mod loader component.
    var loaderComponent: (loader: ModLoader, version: String)? {
        for component in self where component.isEnabled {
            if let loader = ModLoader(uid: component.uid) {
                return (loader, component.version)
            }
        }
        return nil
    }
}
