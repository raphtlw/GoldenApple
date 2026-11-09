import Foundation
import os

/// Saved accounts, Microsoft sign-in, and the sessions that launches use.
nonisolated final class AccountService: Sendable {
    /// A Minecraft token that expires sooner than this is refreshed before a launch.
    private static let refreshMargin: TimeInterval = 12 * 60 * 60
    /// When a refresh cannot reach the services, the old token is still used if it stays valid this long.
    private static let minimumRemainingValidity: TimeInterval = 5 * 60
    private static let refreshTokenErrors: Set<String> = ["invalid_grant", "interaction_required", "consent_required"]

    let store: AccountStore
    private let secrets = AccountSecretStore()
    private let http: HTTPClient
    private let configuration: GoldenAppleConfiguration
    private let settings: SettingsStore

    init(file: URL, http: HTTPClient, configuration: GoldenAppleConfiguration, settings: SettingsStore) {
        store = AccountStore(file: file)
        self.http = http
        self.configuration = configuration
        self.settings = settings
    }

    func load() throws {
        try store.load()
    }

    // MARK: Accounts

    var accounts: [Account] {
        store.list.accounts.map(\.account)
    }

    var defaultAccount: Account? {
        let list = store.list
        return list.defaultAccountID.flatMap(list.record(id:))?.account
    }

    func setDefaultAccount(id: String?) throws {
        try store.update { list in
            if let id, list.record(id: id) == nil {
                throw LauncherError.accountNotFound
            }
            list.defaultAccountID = id
        }
    }

    /// Release builds need a saved Microsoft account that owns Minecraft.
    /// Debug builds skip this check, so the app can be tested before Mojang approves the client ID.
    var canAddOfflineAccounts: Bool {
        #if DEBUG
        true
        #else
        store.list.accounts.contains { $0.kind == .microsoft && $0.ownsMinecraft }
        #endif
    }

    /// Adds an offline account without the ownership check of the public API.
    /// An offline account with the same name is returned instead of a duplicate.
    func addOfflineAccount(name: String) throws -> Account {
        try OfflineProfile.validate(name)
        return try store.update { list in
            if let existing = list.accounts.first(where: { $0.kind == .offline && $0.profileName == name }) {
                return existing.account
            }
            let record = AccountRecord(id: Self.newAccountID(), kind: .offline, profileID: OfflineProfile.profileID(for: name), profileName: name, ownsMinecraft: false)
            Self.add(record, to: &list)
            return record.account
        }
    }

    /// Deletes the account and its Keychain item. When it was the default, the first remaining account becomes the default.
    func remove(id: String) throws {
        guard let record = store.record(id: id) else {
            throw LauncherError.accountNotFound
        }
        if record.kind == .microsoft {
            try secrets.delete(for: id)
        }
        try store.update { list in
            list.accounts.removeAll { $0.id == id }
            if list.defaultAccountID == id {
                list.defaultAccountID = list.accounts.first?.id
            }
        }
    }

    // MARK: Microsoft sign-in

    func signInWithBrowser() async throws -> Account {
        let oauth = try makeOAuth()
        let request = oauth.authorizationRequest()
        let callback = try await BrowserSignIn.callbackURL(opening: request.url, callbackScheme: oauth.callbackScheme)
        let code = try oauth.authorizationCode(from: callback, expectedState: request.state)
        let tokens = try await oauth.redeem(code: code, codeVerifier: request.codeVerifier)
        return try await finishSignIn(tokens, clientID: oauth.clientID)
    }

    func signInWithDeviceCode(onCode: @Sendable (DeviceCode) -> Void) async throws -> Account {
        let oauth = try makeOAuth()
        let grant = try await oauth.requestDeviceCode()
        onCode(grant.code)
        let tokens = try await oauth.waitForTokens(grant)
        return try await finishSignIn(tokens, clientID: oauth.clientID)
    }

    /// Saves a new account, or updates the saved account with the same Minecraft profile.
    private func finishSignIn(_ tokens: MicrosoftTokens, clientID: String) async throws -> Account {
        let signedIn = try await authenticate(tokens)
        let existing = store.list.accounts.first { $0.kind == .microsoft && $0.profileID == signedIn.profile.id }
        var record = existing ?? AccountRecord(id: Self.newAccountID(), kind: .microsoft, profileID: signedIn.profile.id, profileName: signedIn.profile.name, ownsMinecraft: signedIn.ownsMinecraft)
        record.clientID = clientID
        signedIn.apply(to: &record)
        try secrets.save(signedIn.secrets, for: record.id)
        try store.update { Self.add(record, to: &$0) }
        LauncherLog.general.info("Signed in Microsoft account \(record.profileName, privacy: .public)")
        return record.account
    }

    /// The Xbox, XSTS and Minecraft steps after Microsoft tokens are known.
    private func authenticate(_ tokens: MicrosoftTokens) async throws -> SignedInAccount {
        guard let refreshToken = tokens.refreshToken else {
            throw LauncherError.unexpectedResponse(service: "Microsoft sign-in", reason: "no refresh token")
        }
        let xbox = XboxLive(http: http)
        let userToken = try await xbox.userToken(microsoftAccessToken: tokens.accessToken)
        let xsts = try await xbox.minecraftToken(userToken: userToken)
        let minecraft = MinecraftServices(http: http)
        let token = try await minecraft.login(with: xsts)
        let ownsMinecraft = try await minecraft.ownsMinecraft(accessToken: token.accessToken)
        let profile = try await minecraft.profile(accessToken: token.accessToken)
        return SignedInAccount(profile: profile, ownsMinecraft: ownsMinecraft, minecraftToken: token, refreshToken: refreshToken)
    }

    /// Fails with `missingMicrosoftClientID` before any network access when no client ID is set.
    private func makeOAuth(clientID: String? = nil) throws -> MicrosoftOAuth {
        let clientID = (clientID.nonEmpty ?? settings.current.effectiveMicrosoftClientID(configuration)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw LauncherError.missingMicrosoftClientID
        }
        return MicrosoftOAuth(http: http, clientID: clientID, redirectURI: configuration.microsoftRedirectURI)
    }

    // MARK: Launch sessions

    /// The session for a launch. Online Microsoft sessions are refreshed first when the token expires within 12 hours.
    func launchSession(for account: Account?, mode: LaunchMode, status: (String) -> Void) async throws -> LaunchSession {
        switch mode {
        case .demo(let playerName):
            try OfflineProfile.validate(playerName)
            return .offline(playerName: playerName, profileID: OfflineProfile.profileID(for: playerName), isDemo: true)
        case .offline(let playerName):
            guard let account else {
                throw LauncherError.accountRequired
            }
            guard let playerName = playerName.nonEmpty, playerName != account.profileName else {
                return .offline(playerName: account.profileName, profileID: account.profileID)
            }
            try OfflineProfile.validate(playerName)
            return .offline(playerName: playerName, profileID: OfflineProfile.profileID(for: playerName))
        case .online:
            guard let account else {
                throw LauncherError.accountRequired
            }
            guard let record = store.record(id: account.id) else {
                throw LauncherError.accountNotFound
            }
            switch record.kind {
            case .offline:
                return .offline(playerName: record.profileName, profileID: record.profileID)
            case .microsoft:
                return try await microsoftSession(record, status: status)
            }
        }
    }

    private func microsoftSession(_ record: AccountRecord, status: (String) -> Void) async throws -> LaunchSession {
        guard !record.needsSignIn, let saved = try secrets.secrets(for: record.id) else {
            try markNeedsSignIn(record.id)
            throw LauncherError.accountNeedsSignIn(record.profileName)
        }
        let remaining = saved.minecraftTokenExpiry.timeIntervalSinceNow
        guard remaining < Self.refreshMargin else {
            return .microsoft(playerName: record.profileName, profileID: record.profileID, accessToken: saved.minecraftAccessToken)
        }

        status("Refreshing the Microsoft sign-in")
        do {
            let refreshed = try await refresh(record, refreshToken: saved.refreshToken)
            return .microsoft(playerName: refreshed.profileName, profileID: refreshed.profileID, accessToken: refreshed.accessToken)
        } catch let error where Self.isServiceUnreachable(error) {
            LauncherLog.general.error("Account refresh failed: \(error.localizedDescription, privacy: .public)")
            guard remaining > Self.minimumRemainingValidity else {
                throw LauncherError.accountRefreshUnavailable(record.profileName)
            }
            status("Microsoft could not be reached. Using the current sign-in.")
            return .microsoft(playerName: record.profileName, profileID: record.profileID, accessToken: saved.minecraftAccessToken)
        } catch LauncherError.microsoftSignInFailed(let code, _) where Self.refreshTokenErrors.contains(code) {
            try markNeedsSignIn(record.id)
            throw LauncherError.accountNeedsSignIn(record.profileName)
        }
    }

    /// Runs the whole sign-in chain with the refresh token and saves the new tokens and profile.
    private func refresh(_ record: AccountRecord, refreshToken: String) async throws -> (profileName: String, profileID: String, accessToken: String) {
        let oauth = try makeOAuth(clientID: record.clientID)
        let signedIn = try await authenticate(try await oauth.refresh(refreshToken))
        var updated = record
        signedIn.apply(to: &updated)
        try secrets.save(signedIn.secrets, for: record.id)
        try store.update { $0.save(updated) }
        return (updated.profileName, updated.profileID, signedIn.minecraftToken.accessToken)
    }

    private func markNeedsSignIn(_ id: String) throws {
        try store.update { list in
            guard var record = list.record(id: id), !record.needsSignIn else {
                return
            }
            record.needsSignIn = true
            list.save(record)
        }
    }

    // MARK: Helpers

    /// Network errors and server errors. Refusals such as an invalid token are not included.
    private static func isServiceUnreachable(_ error: any Error) -> Bool {
        switch error as? LauncherError {
        case .networkFailure: true
        case .httpStatus(_, let statusCode): statusCode >= 500
        default: false
        }
    }

    /// Saves the record and makes it the default when no default exists.
    private static func add(_ record: AccountRecord, to list: inout AccountList) {
        list.save(record)
        if list.defaultAccountID.flatMap(list.record(id:)) == nil {
            list.defaultAccountID = record.id
        }
    }

    private static func newAccountID() -> String {
        UUID().uuidString.lowercased()
    }
}

/// The result of the Xbox and Minecraft steps.
nonisolated private struct SignedInAccount {
    let profile: MinecraftProfile
    let ownsMinecraft: Bool
    let minecraftToken: MinecraftToken
    let refreshToken: String

    var secrets: AccountSecrets {
        AccountSecrets(refreshToken: refreshToken, minecraftAccessToken: minecraftToken.accessToken, minecraftTokenExpiry: minecraftToken.expiresAt)
    }

    func apply(to record: inout AccountRecord) {
        record.profileID = profile.id
        record.profileName = profile.name
        record.skinURL = profile.skinURL
        record.ownsMinecraft = ownsMinecraft
        record.lastRefreshed = Date()
        record.needsSignIn = false
    }
}
