import Foundation

/// A saved account as the app shows it. Tokens are never part of this value.
nonisolated struct Account: Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case microsoft
        case offline
    }

    let id: String
    let kind: Kind
    let profileName: String
    /// The Minecraft profile UUID as 32 lowercase hexadecimal digits.
    let profileID: String
    let ownsMinecraft: Bool
    /// The Microsoft sign-in stopped working. The player must sign in again before playing online.
    let needsSignIn: Bool
}

/// The code a player enters at `verificationURL` to finish a device code sign-in.
nonisolated struct DeviceCode: Hashable, Sendable {
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
}

/// One entry of `Accounts.json`. Secrets are stored in the Keychain, see `AccountSecrets`.
nonisolated struct AccountRecord: Codable, Hashable, Sendable {
    var id: String
    var kind: Account.Kind
    var profileID: String
    var profileName: String
    var skinURL: URL?
    var ownsMinecraft: Bool
    /// The Microsoft client ID the refresh token belongs to.
    var clientID: String?
    var lastRefreshed: Date?
    var needsSignIn = false

    init(id: String, kind: Account.Kind, profileID: String, profileName: String, ownsMinecraft: Bool) {
        self.id = id
        self.kind = kind
        self.profileID = profileID
        self.profileName = profileName
        self.ownsMinecraft = ownsMinecraft
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, profileID, profileName, skinURL, ownsMinecraft, clientID, lastRefreshed, needsSignIn
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Account.Kind.self, forKey: .kind)
        profileID = try container.decode(String.self, forKey: .profileID)
        profileName = try container.decode(String.self, forKey: .profileName)
        skinURL = try container.decodeIfPresent(URL.self, forKey: .skinURL)
        ownsMinecraft = try container.decodeIfPresent(Bool.self, forKey: .ownsMinecraft) ?? false
        clientID = try container.decodeIfPresent(String.self, forKey: .clientID)
        lastRefreshed = try container.decodeIfPresent(Date.self, forKey: .lastRefreshed)
        needsSignIn = try container.decodeIfPresent(Bool.self, forKey: .needsSignIn) ?? false
    }

    var account: Account {
        Account(id: id, kind: kind, profileName: profileName, profileID: profileID, ownsMinecraft: ownsMinecraft, needsSignIn: needsSignIn)
    }
}

/// The secrets of a Microsoft account, stored as JSON in one Keychain item per account.
nonisolated struct AccountSecrets: Codable, Sendable {
    var refreshToken: String
    var minecraftAccessToken: String
    var minecraftTokenExpiry: Date
}
