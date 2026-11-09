import Foundation

/// Replaces `${name}` placeholders in launch arguments. Unknown names become empty text.
nonisolated struct LaunchTokens: Sendable {
    private let values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    func replacing(in text: String) -> String {
        var result = ""
        var rest = text[...]
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else {
                return result + rest[start.lowerBound...]
            }
            result += values[String(rest[start.upperBound..<end])] ?? ""
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }
}
