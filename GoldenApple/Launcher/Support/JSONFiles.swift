import Foundation

/// Reading and writing JSON. GoldenApple's own files are pretty-printed with sorted keys and carry `"formatVersion": 1`.
nonisolated enum JSONFiles {
    static let ownFormatVersion = 1

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Accepts ISO 8601 dates with or without fractional seconds and with any time zone offset.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date “\(text)”")
            }
            return date
        }
        return decoder
    }

    static func parseDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, name: String) throws -> Value {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch {
            throw LauncherError.unreadableFile(path: name, reason: describe(error))
        }
    }

    static func read<Value: Decodable>(_ type: Value.Type, from file: URL) throws -> Value {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw LauncherError.unreadableFile(path: file.path, reason: error.localizedDescription)
        }
        return try decode(type, from: data, name: file.path)
    }

    static func write(_ value: some Encodable, to file: URL) throws {
        try FileSystem.writeAtomically(try makeEncoder().encode(value), to: file)
    }

    /// Reads one of GoldenApple's own files and checks its `formatVersion`.
    static func readOwnFile<Value: Decodable>(_ type: Value.Type, from file: URL) throws -> Value {
        let versioned = try read(OwnFile<Value>.self, from: file)
        guard versioned.formatVersion == ownFormatVersion else {
            throw LauncherError.unsupportedFormatVersion(file: file.lastPathComponent, version: versioned.formatVersion)
        }
        return versioned.content
    }

    /// Writes one of GoldenApple's own files with `"formatVersion": 1` next to the value's keys.
    static func writeOwnFile<Value: Encodable>(_ value: Value, to file: URL) throws {
        try write(OwnFile(content: value, formatVersion: ownFormatVersion), to: file)
    }

    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key “\(key.stringValue)” at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "the top level" : path
    }
}

/// Adds `formatVersion` to the top-level object of the wrapped value.
nonisolated private struct OwnFile<Content> {
    var content: Content
    var formatVersion: Int

    private enum CodingKeys: String, CodingKey {
        case formatVersion
    }
}

nonisolated extension OwnFile: Decodable where Content: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? JSONFiles.ownFormatVersion
        content = try Content(from: decoder)
    }
}

nonisolated extension OwnFile: Encodable where Content: Encodable {
    func encode(to encoder: any Encoder) throws {
        try content.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
    }
}
