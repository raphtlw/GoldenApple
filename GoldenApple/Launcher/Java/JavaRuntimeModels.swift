import Foundation

/// A downloadable Java runtime from a `net.minecraft.java`, `com.azul.java` or `net.adoptium.java` document.
nonisolated struct JavaRuntime: Decodable, Hashable, Sendable {
    struct RuntimeChecksum: Decodable, Hashable, Sendable {
        let type: String
        let hash: String
    }

    struct RuntimeVersion: Decodable, Hashable, Sendable {
        let major: Int
        let minor: Int?
        let security: Int?
        let build: Int?
        let name: String?
    }

    static let macOSARM64 = "mac-os-arm64"

    let name: String
    let vendor: String?
    let runtimeOS: String
    /// `manifest` for a Mojang file manifest, `archive` for a zip or tar.gz.
    let downloadType: String
    let packageType: String?
    let url: URL
    let checksum: RuntimeChecksum?
    let version: RuntimeVersion?

    var expectedChecksum: Checksum? {
        checksum.flatMap { Checksum(type: $0.type, value: $0.hash) }
    }
}

/// A Mojang runtime file manifest.
nonisolated struct RuntimeManifest: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        struct Downloads: Decodable, Sendable {
            let raw: DownloadArtifact?
        }

        /// `file`, `directory` or `link`.
        let type: String
        let executable: Bool?
        let target: String?
        let downloads: Downloads?
    }

    let files: [String: Entry]
}
