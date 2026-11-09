import Foundation

extension GoldenAppleLauncher {
    func accounts() -> [Account] {
        services.accounts.accounts
    }

    func defaultAccount() -> Account? {
        services.accounts.defaultAccount
    }

    func setDefaultAccount(_ account: Account?) throws {
        try services.accounts.setDefaultAccount(id: account?.id)
    }

    /// Presents the Microsoft sign-in with `ASWebAuthenticationSession` on the main actor, anchored to the key window.
    func signInWithMicrosoft() async throws -> Account {
        try await services.accounts.signInWithBrowser()
    }

    /// `onCode` receives the code to show to the player. The call returns when the player finished the sign-in.
    func signInWithDeviceCode(onCode: @Sendable (DeviceCode) -> Void) async throws -> Account {
        try await services.accounts.signInWithDeviceCode(onCode: onCode)
    }

    /// Release builds need a saved Microsoft account that owns Minecraft. Debug builds do not.
    func addOfflineAccount(name: String) throws -> Account {
        guard services.accounts.canAddOfflineAccounts else {
            throw LauncherError.offlineAccountsNeedMicrosoftAccount
        }
        return try services.accounts.addOfflineAccount(name: name)
    }

    func removeAccount(_ account: Account) throws {
        try services.accounts.remove(id: account.id)
    }
}
