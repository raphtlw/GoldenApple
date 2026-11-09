import Foundation

/// Makes the components of an instance consistent: adds required packages, removes unused volatile ones,
/// applies exact version requirements, and rejects conflicts.
nonisolated struct ComponentResolver: Sendable {
    enum Mode: Sendable {
        /// Return the corrected component list.
        case apply
        /// Any change that would be needed is an error. Used before a launch.
        case check
    }

    /// The combined requirement of all enabled components on one package.
    private struct CombinedRequirement {
        let uid: String
        var equals: String?
        var equalsRequiredBy: String?
        var suggests: String?
    }

    private static let maximumPasses = 20

    let metadata: MetadataClient
    let catalog: VersionCatalog

    func resolve(_ components: [InstanceComponent], mode: Mode = .apply, metadataMode: MetadataMode = .online) async throws -> [InstanceComponent] {
        var current = components
        for _ in 0..<Self.maximumPasses {
            let documents = try await documentsByUID(for: current, metadataMode: metadataMode)
            let next = try await resolvePass(current, documents: documents, metadataMode: metadataMode)
            if next == current {
                try checkConflicts(current, documents: documents)
                return current
            }
            if mode == .check {
                throw LauncherError.componentsNeedUpdate(Self.describeChanges(from: current, to: next))
            }
            current = next
        }
        throw LauncherError.resolutionDidNotFinish
    }

    /// Changes the Minecraft version, moves every loader to its recommended version for it, and resolves again.
    /// Dependency components are removed first, so LWJGL and mappings are chosen again for the new version.
    func changeMinecraftVersion(of components: [InstanceComponent], to version: String, metadataMode: MetadataMode = .online) async throws -> [InstanceComponent] {
        guard let minecraftIndex = components.firstIndex(where: { $0.uid == ComponentID.minecraft }) else {
            throw LauncherError.missingMinecraftComponent(version)
        }
        guard components[minecraftIndex].version != version else {
            return try await resolve(components, metadataMode: metadataMode)
        }
        var changed = components
        changed[minecraftIndex].version = version
        changed.removeAll(where: \.isDependency)
        for index in changed.indices {
            if let loader = ModLoader(uid: changed[index].uid) {
                changed[index].version = try await catalog.recommendedLoaderVersion(loader, minecraftVersion: version, mode: metadataMode)
            }
        }
        return try await resolve(changed, metadataMode: metadataMode)
    }

    /// The version documents of the enabled components, in component order.
    func documents(for components: [InstanceComponent], metadataMode: MetadataMode) async throws -> [VersionDocument] {
        var documents: [VersionDocument] = []
        for component in components where component.isEnabled {
            documents.append(try await metadata.versionDocument(component.uid, version: component.version, mode: metadataMode))
        }
        return documents
    }

    /// The merged launch profile of the enabled components.
    func profile(for components: [InstanceComponent], metadataMode: MetadataMode) async throws -> LaunchProfile {
        LaunchProfile(merging: try await documents(for: components, metadataMode: metadataMode))
    }

    // MARK: One pass

    private func documentsByUID(for components: [InstanceComponent], metadataMode: MetadataMode) async throws -> [String: VersionDocument] {
        let documents = try await documents(for: components, metadataMode: metadataMode)
        return Dictionary(documents.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func resolvePass(_ components: [InstanceComponent], documents: [String: VersionDocument], metadataMode: MetadataMode) async throws -> [InstanceComponent] {
        var next = components

        // Remove volatile dependencies that nothing requires anymore, until stable.
        var requirements = try Self.requirements(of: next, documents: documents)
        while let index = next.firstIndex(where: { component in
            component.isDependency && documents[component.uid]?.isVolatile == true && !requirements.contains { $0.uid == component.uid }
        }) {
            next.remove(at: index)
            requirements = try Self.requirements(of: next, documents: documents)
        }

        // Add missing requirements as dependencies.
        for requirement in requirements where next.component(requirement.uid) == nil {
            let version = try await versionForNewDependency(requirement, minecraftVersion: next.minecraftVersion, metadataMode: metadataMode)
            next.append(.dependency(requirement.uid, version: version))
        }

        // Apply exact version requirements.
        for requirement in requirements {
            guard let equals = requirement.equals, let index = next.firstIndex(where: { $0.uid == requirement.uid }), next[index].version != equals else {
                continue
            }
            guard !next[index].isPinned else {
                throw LauncherError.pinnedComponentMismatch(
                    component: requirement.uid,
                    version: next[index].version,
                    requiredBy: requirement.equalsRequiredBy ?? "",
                    requiredVersion: equals
                )
            }
            next[index].version = equals
        }
        return next
    }

    /// All `requires` of the enabled components, combined per package.
    private static func requirements(of components: [InstanceComponent], documents: [String: VersionDocument]) throws -> [CombinedRequirement] {
        var combined: [CombinedRequirement] = []
        for component in components where component.isEnabled {
            for requirement in documents[component.uid]?.requires ?? [] {
                guard let index = combined.firstIndex(where: { $0.uid == requirement.uid }) else {
                    combined.append(CombinedRequirement(
                        uid: requirement.uid,
                        equals: requirement.equals,
                        equalsRequiredBy: requirement.equals == nil ? nil : component.uid,
                        suggests: requirement.suggests
                    ))
                    continue
                }
                try merge(requirement, from: component.uid, into: &combined[index])
            }
        }
        return combined
    }

    private static func merge(_ requirement: Requirement, from requirer: String, into combined: inout CombinedRequirement) throws {
        if let equals = requirement.equals {
            if let existing = combined.equals, existing != equals {
                throw LauncherError.conflictingRequirements(
                    uid: requirement.uid,
                    firstComponent: combined.equalsRequiredBy ?? "",
                    firstVersion: existing,
                    secondComponent: requirer,
                    secondVersion: equals
                )
            }
            combined.equals = equals
            combined.equalsRequiredBy = combined.equalsRequiredBy ?? requirer
        }
        if let suggests = requirement.suggests {
            if let existing = combined.suggests, !VersionComparison.isNewer(suggests, than: existing) {
                return
            }
            combined.suggests = suggests
        }
    }

    /// `equals`, else `suggests`, else the Minecraft version for mappings, else the newest release.
    private func versionForNewDependency(_ requirement: CombinedRequirement, minecraftVersion: String?, metadataMode: MetadataMode) async throws -> String {
        if let version = requirement.equals ?? requirement.suggests {
            return version
        }
        if ComponentID.mappingsNamedAfterMinecraft.contains(requirement.uid), let minecraftVersion {
            return minecraftVersion
        }
        return try await catalog.newestRelease(of: requirement.uid, mode: metadataMode)
    }

    // MARK: Conflicts

    private func checkConflicts(_ components: [InstanceComponent], documents: [String: VersionDocument]) throws {
        let enabled = components.filter(\.isEnabled)
        let loaders = enabled.filter { ModLoader(uid: $0.uid) != nil }
        if loaders.count > 1 {
            throw LauncherError.componentConflict(loaders[0].uid, loaders[1].uid)
        }
        for component in enabled {
            for conflict in documents[component.uid]?.conflicts ?? [] {
                guard let other = enabled.component(conflict.uid) else {
                    continue
                }
                if conflict.equals == nil || conflict.equals == other.version {
                    throw LauncherError.componentConflict(component.uid, other.uid)
                }
            }
        }
    }

    private static func describeChanges(from old: [InstanceComponent], to new: [InstanceComponent]) -> String {
        var changes: [String] = []
        for component in new {
            if let previous = old.component(component.uid) {
                if previous.version != component.version {
                    changes.append("\(component.name) \(previous.version) should be \(component.version)")
                }
            } else {
                changes.append("\(component.name) \(component.version) is missing")
            }
        }
        for component in old where new.component(component.uid) == nil {
            changes.append("\(component.name) is not needed")
        }
        return changes.joined(separator: ", ")
    }
}
