import CryptoKit
import Foundation

nonisolated enum HashAlgorithm: String, Codable, Sendable {
    case sha1
    case sha256
    case sha512
    case md5
}

/// An expected hash for a file, as lowercase hexadecimal text.
nonisolated struct Checksum: Hashable, Sendable {
    let algorithm: HashAlgorithm
    let value: String

    init(_ algorithm: HashAlgorithm, _ value: String) {
        self.algorithm = algorithm
        self.value = value.lowercased()
    }

    /// Accepts the metadata spelling of algorithm names, for example `sha1` or `sha256`.
    init?(type: String, value: String) {
        guard let algorithm = HashAlgorithm(rawValue: type.lowercased().replacing("-", with: "")) else {
            return nil
        }
        self.init(algorithm, value)
    }

    /// Throws `checksumMismatch` when the file does not have this hash.
    func verify(_ file: URL) async throws {
        let actual = try await Hashing.hash(of: file, algorithm: algorithm)
        guard actual == value else {
            throw LauncherError.checksumMismatch(file: file.lastPathComponent, expected: value, actual: actual)
        }
    }

    func verify(_ data: Data, name: String) throws {
        let actual = Hashing.hash(of: data, algorithm: algorithm)
        guard actual == value else {
            throw LauncherError.checksumMismatch(file: name, expected: value, actual: actual)
        }
    }

    func matches(_ file: URL) async -> Bool {
        (try? await Hashing.hash(of: file, algorithm: algorithm)) == value
    }
}

/// File and data hashing with CryptoKit. Files are read in 1 MiB chunks.
nonisolated enum Hashing {
    private static let chunkSize = 1_048_576

    @concurrent
    static func hash(of file: URL, algorithm: HashAlgorithm) async throws -> String {
        switch algorithm {
        case .sha1: try digest(Insecure.SHA1.self, of: file)
        case .sha256: try digest(SHA256.self, of: file)
        case .sha512: try digest(SHA512.self, of: file)
        case .md5: try digest(Insecure.MD5.self, of: file)
        }
    }

    static func hash(of data: Data, algorithm: HashAlgorithm) -> String {
        switch algorithm {
        case .sha1: hexadecimal(Insecure.SHA1.hash(data: data))
        case .sha256: hexadecimal(SHA256.hash(data: data))
        case .sha512: hexadecimal(SHA512.hash(data: data))
        case .md5: hexadecimal(Insecure.MD5.hash(data: data))
        }
    }

    private static func digest<Function: HashFunction>(_ function: Function.Type, of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = Function()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hexadecimal(hasher.finalize())
    }

    private static func hexadecimal(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
