import Foundation
import Observation

/// App-wide state: the launcher and whether onboarding is complete.
/// The completion flag is stored in the launcher `Settings.json`, so all app data stays in one folder.
@MainActor
@Observable
final class AppModel {
    let launcher = GoldenAppleLauncher()
    private(set) var isReady = false
    private(set) var hasCompletedOnboarding = false
    private(set) var startupError: String?

    /// Creates the data folders, loads settings and accounts, and reads the onboarding flag.
    func prepare() async {
        guard !isReady else {
            return
        }
        do {
            try await launcher.prepare()
            hasCompletedOnboarding = await launcher.settings().onboardingCompleted
            isReady = true
        } catch {
            startupError = error.localizedDescription
        }
    }

    func completeOnboarding() {
        setOnboardingCompleted(true)
    }

    /// Shows onboarding again, for example from a debug menu.
    func resetOnboarding() {
        setOnboardingCompleted(false)
    }

    private func setOnboardingCompleted(_ completed: Bool) {
        hasCompletedOnboarding = completed
        Task {
            do {
                try await launcher.updateSettings { $0.onboardingCompleted = completed }
            } catch {
                startupError = error.localizedDescription
            }
        }
    }
}
