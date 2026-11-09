import Foundation

/// A parsed `java.version`: `1.<major>.<minor>_<security>` for Java 8 and older,
/// `<major>.<minor>.<security>` for newer versions.
nonisolated struct JavaVersion: Comparable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let security: Int

    init?(_ text: String) {
        let numbers = text
            .split(whereSeparator: { !$0.isNumber })
            .map { Int($0) ?? 0 }
        guard let first = numbers.first else {
            return nil
        }
        let isLegacy = first == 1 && numbers.count > 1
        let parts = isLegacy ? Array(numbers.dropFirst()) : numbers
        major = parts[0]
        minor = parts.count > 1 ? parts[1] : 0
        security = parts.count > 2 ? parts[2] : 0
    }

    static func < (lhs: JavaVersion, rhs: JavaVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.security) < (rhs.major, rhs.minor, rhs.security)
    }
}
