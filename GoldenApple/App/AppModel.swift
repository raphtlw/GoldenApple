import Foundation
import Observation

/// App-wide state: the launcher and the onboarding, while it is not complete.
/// The completion flag is stored in the launcher `Settings.json` and the onboarding progress in `Onboarding.json`,
/// so all app data stays in one folder.
@MainActor
@Observable
final class AppModel {
    let launcher = GoldenAppleLauncher()
    private(set) var isReady = false
    /// Set while onboarding is not complete.
    private(set) var onboarding: OnboardingModel?
    private(set) var startupError: String?

    private var onboardingStore: OnboardingProgressStore {
        OnboardingProgressStore(file: launcher.paths.onboardingFile)
    }

    /// Creates the data folders, loads settings and accounts, and continues the onboarding when it is not complete.
    func prepare() async {
        guard !isReady else {
            return
        }
        do {
            try await launcher.prepare()
            if await !launcher.settings().onboardingCompleted {
                onboarding = OnboardingModel(launcher: launcher, store: onboardingStore)
            }
            isReady = true
        } catch {
            startupError = error.localizedDescription
        }
    }

    func completeOnboarding() {
        onboarding?.discardProgress()
        onboarding = nil
        saveOnboardingCompleted(true)
    }

    /// Shows onboarding again from the start, for example from a debug menu.
    func resetOnboarding() {
        let store = onboardingStore
        store.remove()
        onboarding = OnboardingModel(launcher: launcher, store: store)
        saveOnboardingCompleted(false)
    }

    private func saveOnboardingCompleted(_ completed: Bool) {
        Task {
            do {
                try await launcher.updateSettings { $0.onboardingCompleted = completed }
            } catch {
                startupError = error.localizedDescription
            }
        }
    }
}
