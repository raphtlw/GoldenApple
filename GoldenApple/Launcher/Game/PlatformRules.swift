import Foundation

/// Decides which libraries apply to this Mac. GoldenApple runs arm64 Java, so its OS key is `osx-arm64`.
/// The Intel key `osx` never matches.
nonisolated enum PlatformRules {
    static let operatingSystemKey = "osx-arm64"
    private static let architectureBits = "64"

    /// A library without rules is active. With rules, it starts disallowed and the last rule that applies decides.
    static func isActive(_ library: Library) -> Bool {
        guard let rules = library.rules else {
            return true
        }
        var allowed = false
        for rule in rules where applies(rule) {
            allowed = rule.action == .allow
        }
        return allowed
    }

    /// The natives classifier for this Mac, or nil when the library has no `osx-arm64` natives.
    static func nativeClassifier(_ library: Library) -> String? {
        library.natives?[operatingSystemKey]?.replacing("${arch}", with: architectureBits)
    }

    /// A rule without `os` always applies. A rule with `os` applies only when its name is this Mac's key.
    private static func applies(_ rule: PlatformRule) -> Bool {
        guard let os = rule.os else {
            return true
        }
        return os.name == operatingSystemKey
    }
}
