import Foundation

/// Everything the enabled components of an instance add to a launch, merged in ascending `order`.
nonisolated struct LaunchProfile: Sendable {
    var minecraftVersion: String?
    var minecraftVersionType: String?
    /// The last non-empty value wins.
    var mainClass: String?
    /// The last non-empty value wins.
    var minecraftArguments: String?
    var jvmArguments: [String] = []
    var traits: Set<String> = []
    /// A repeated tweaker moves to the end.
    var tweakers: [String] = []
    var mainJar: Library?
    /// Class path libraries active on this Mac.
    var libraries: [Library] = []
    /// Libraries with natives for `osx-arm64`.
    var nativeLibraries: [Library] = []
    /// Every version is kept, because installer processors ask for exact versions.
    var mavenFiles: [Library] = []
    var agents: [JavaAgent] = []
    var assetIndex: AssetIndexReference?
    var compatibleJavaMajors: [Int] = []
    var compatibleJavaName: String?

    init(merging documents: [VersionDocument]) {
        let ordered = documents.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
        for document in ordered {
            apply(document)
        }
    }

    func hasTrait(_ trait: String) -> Bool {
        traits.contains(trait)
    }

    private mutating func apply(_ document: VersionDocument) {
        if document.uid == ComponentID.minecraft {
            minecraftVersion = document.version
            minecraftVersionType = document.type
        }
        mainClass = document.mainClass.nonEmpty ?? mainClass
        minecraftArguments = document.minecraftArguments.nonEmpty ?? minecraftArguments
        jvmArguments += document.jvmArguments
        traits.formUnion(document.traits)
        for tweaker in document.tweakers {
            tweakers.removeAll { $0 == tweaker }
            tweakers.append(tweaker)
        }
        mainJar = document.mainJar ?? mainJar
        assetIndex = document.assetIndex ?? assetIndex
        if !document.compatibleJavaMajors.isEmpty {
            compatibleJavaMajors = document.compatibleJavaMajors
        }
        compatibleJavaName = document.compatibleJavaName.nonEmpty ?? compatibleJavaName

        for library in document.libraries where PlatformRules.isActive(library) {
            if library.natives == nil {
                Self.add(library, to: &libraries)
            } else if PlatformRules.nativeClassifier(library) != nil {
                Self.add(library, to: &nativeLibraries)
            }
        }
        for library in document.mavenFiles where PlatformRules.isActive(library) && !mavenFiles.contains(where: { $0.name == library.name }) {
            mavenFiles.append(library)
        }
        agents += document.agents.filter { PlatformRules.isActive($0.library) }
    }

    /// Adds a library, or replaces the one with the same group, artifact and classifier when this version is higher.
    /// A replacement keeps the position of the earlier library.
    private static func add(_ library: Library, to list: inout [Library]) {
        guard let coordinate = library.coordinate else {
            list.append(library)
            return
        }
        guard let index = list.firstIndex(where: { $0.coordinate?.identity == coordinate.identity }) else {
            list.append(library)
            return
        }
        if let existingVersion = list[index].coordinate?.version, VersionComparison.isNewer(coordinate.version, than: existingVersion) {
            list[index] = library
        }
    }
}
