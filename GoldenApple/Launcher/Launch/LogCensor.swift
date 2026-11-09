import Foundation
import Synchronization

/// Replaces the access token, the session value and the profile ID in log text.
nonisolated struct LogCensor: Sendable {
    private struct Replacement: Hashable, Sendable {
        let secret: String
        let placeholder: String
    }

    static let accessTokenPlaceholder = "<ACCESS TOKEN>"
    static let sessionPlaceholder = "<SESSION>"
    static let profileIDPlaceholder = "<PROFILE ID>"

    /// The secrets of every launch since the launcher started. Error reports have no session, so they use these.
    private static let launchSecrets = Mutex<[Replacement]>([])

    private let replacements: [Replacement]

    init(session: LaunchSession) {
        var replacements: [Replacement] = []
        if session.isAuthenticated {
            replacements.append(Replacement(secret: session.sessionValue, placeholder: Self.sessionPlaceholder))
            replacements.append(Replacement(secret: session.accessToken, placeholder: Self.accessTokenPlaceholder))
        }
        replacements.append(Replacement(secret: session.profileID, placeholder: Self.profileIDPlaceholder))
        if let dashed = Self.dashedUUID(session.profileID) {
            replacements.append(Replacement(secret: dashed, placeholder: Self.profileIDPlaceholder))
        }
        self.init(replacements.filter { !$0.secret.isEmpty })
        Self.remember(self.replacements)
    }

    private init(_ replacements: [Replacement]) {
        // The session value contains the token and the profile ID, so longer secrets are replaced first.
        self.replacements = replacements.sorted { $0.secret.count > $1.secret.count }
    }

    /// A censor for the secrets of all launches so far.
    static func forLaunchSecrets() -> LogCensor {
        LogCensor(launchSecrets.withLock { $0 })
    }

    func censor(_ text: String) -> String {
        replacements.reduce(text) { text, replacement in
            text.replacing(replacement.secret, with: replacement.placeholder)
        }
    }

    /// Also replaces text shaped like a Minecraft access token (a JSON Web Token), for text that may hold
    /// a token from outside a launch.
    func censorIncludingTokenShapes(_ text: String) -> String {
        censor(text).replacing(#/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/#, with: Self.accessTokenPlaceholder)
    }

    private static func remember(_ replacements: [Replacement]) {
        launchSecrets.withLock { known in
            known += replacements.filter { !known.contains($0) }
        }
    }

    private static func dashedUUID(_ hexadecimal: String) -> String? {
        guard hexadecimal.count == 32 else {
            return nil
        }
        var text = hexadecimal
        for offset in [20, 16, 12, 8] {
            text.insert("-", at: text.index(text.startIndex, offsetBy: offset))
        }
        return text
    }
}
