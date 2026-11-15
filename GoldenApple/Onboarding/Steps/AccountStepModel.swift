import Foundation
import Observation

/// Sign-in for the account step. A signed-in or added account becomes the default account.
@MainActor
@Observable
final class AccountStepModel {
    enum Activity: Equatable {
        case idle
        case signingInWithBrowser
        /// The code is nil until Microsoft sends it.
        case waitingForDeviceCode(DeviceCode?)
    }

    private let launcher: GoldenAppleLauncher
    private(set) var account: Account?
    private(set) var activity = Activity.idle
    private(set) var errorMessage: String?
    private(set) var canAddOfflineAccounts = false
    var offlineName = ""
    private var signInTask: Task<Void, Never>?

    init(launcher: GoldenAppleLauncher) {
        self.launcher = launcher
    }

    var isBusy: Bool {
        activity != .idle
    }

    var isOfflineNameValid: Bool {
        OfflineProfile.isValidName(offlineName)
    }

    func load() async {
        account = await launcher.defaultAccount()
        canAddOfflineAccounts = await launcher.canAddOfflineAccounts()
    }

    func signInWithBrowser() {
        signIn(.signingInWithBrowser) { launcher in
            try await launcher.signInWithMicrosoft()
        }
    }

    func signInWithDeviceCode() {
        signIn(.waitingForDeviceCode(nil)) { launcher in
            try await launcher.signInWithDeviceCode { code in
                Task { @MainActor in self.showDeviceCode(code) }
            }
        }
    }

    /// Ignores a code that arrives after the sign-in was cancelled.
    private func showDeviceCode(_ code: DeviceCode) {
        if activity == .waitingForDeviceCode(nil) {
            activity = .waitingForDeviceCode(code)
        }
    }

    func addOfflineAccount() {
        guard isOfflineNameValid, !isBusy else {
            return
        }
        let name = offlineName
        errorMessage = nil
        Task {
            do {
                let added = try await launcher.addOfflineAccount(name: name)
                try await launcher.setDefaultAccount(added)
                account = added
                offlineName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        activity = .idle
    }

    /// Shows the sign-in choices again. The current account stays saved.
    func chooseAnotherAccount() {
        account = nil
        errorMessage = nil
    }

    private func signIn(_ activity: Activity, using work: @escaping @MainActor (GoldenAppleLauncher) async throws -> Account) {
        cancelSignIn()
        errorMessage = nil
        self.activity = activity
        let launcher = launcher
        signInTask = Task {
            do {
                let signedIn = try await work(launcher)
                try await launcher.setDefaultAccount(signedIn)
                account = signedIn
            } catch is CancellationError {
            } catch LauncherError.signInCancelled {
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                self.activity = .idle
                signInTask = nil
            }
        }
    }
}
