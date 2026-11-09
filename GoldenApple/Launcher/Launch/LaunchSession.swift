import Foundation

/// The player identity and credentials a launch passes to the game.
nonisolated struct LaunchSession: Sendable {
    let playerName: String
    /// 32 hexadecimal digits without dashes.
    let profileID: String
    /// The Minecraft access token, or `0` without Microsoft sign-in.
    let accessToken: String
    /// `msa` for Microsoft sessions, `legacy` for offline and demo sessions.
    let userType: String
    let isDemo: Bool

    static func microsoft(playerName: String, profileID: String, accessToken: String) -> LaunchSession {
        LaunchSession(playerName: playerName, profileID: profileID, accessToken: accessToken, userType: "msa", isDemo: false)
    }

    static func offline(playerName: String, profileID: String, isDemo: Bool = false) -> LaunchSession {
        LaunchSession(playerName: playerName, profileID: profileID, accessToken: "0", userType: "legacy", isDemo: isDemo)
    }

    var isAuthenticated: Bool {
        userType == "msa"
    }

    /// The `${auth_session}` value.
    var sessionValue: String {
        isAuthenticated ? "token:\(accessToken):\(profileID)" : "-"
    }
}
