import Foundation

/// A parsed `group:artifact:version[:classifier][@extension]` library name.
nonisolated struct MavenCoordinate: Hashable, Sendable {
    let group: String
    let artifact: String
    let version: String
    let classifier: String?
    let fileExtension: String

    init(group: String, artifact: String, version: String, classifier: String? = nil, fileExtension: String = "jar") {
        self.group = group
        self.artifact = artifact
        self.version = version
        self.classifier = classifier
        self.fileExtension = fileExtension
    }

    init?(_ name: String) {
        var coordinates = Substring(name)
        var fileExtension = "jar"
        if let at = name.lastIndex(of: "@") {
            fileExtension = String(name[name.index(after: at)...])
            coordinates = name[..<at]
        }
        let parts = coordinates.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 4, !parts.contains(where: \.isEmpty), !fileExtension.isEmpty else {
            return nil
        }
        self.init(
            group: parts[0],
            artifact: parts[1],
            version: parts[2],
            classifier: parts.count == 4 ? parts[3] : nil,
            fileExtension: fileExtension
        )
    }

    func withClassifier(_ classifier: String) -> MavenCoordinate {
        MavenCoordinate(group: group, artifact: artifact, version: version, classifier: classifier, fileExtension: fileExtension)
    }

    /// Identifies a library across versions: group, artifact and classifier.
    var identity: String {
        [group, artifact, classifier ?? ""].joined(separator: ":")
    }

    var fileName: String {
        let suffix = classifier.map { "-\($0)" } ?? ""
        return "\(artifact)-\(version)\(suffix).\(fileExtension)"
    }

    /// `group/with/slashes/artifact/version/artifact-version[-classifier].ext`
    var relativePath: String {
        [group.replacing(".", with: "/"), artifact, version, fileName].joined(separator: "/")
    }

    var isGameJar: Bool {
        group == "com.mojang" && artifact == "minecraft" && classifier == "client"
    }
}
