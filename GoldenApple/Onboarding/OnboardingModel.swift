import Foundation
import Observation

/// Onboarding state. Every change to `progress` is saved at once, so onboarding continues where it stopped after a quit.
@MainActor
@Observable
final class OnboardingModel {
    typealias Step = OnboardingStep

    /// The way the last step change went. Step transitions use it to slide in from the correct side.
    enum Direction {
        case forward
        case backward
    }

    let launcher: GoldenAppleLauncher
    private let store: OnboardingProgressStore
    private(set) var progress: OnboardingProgress
    private(set) var direction = Direction.forward

    var step: Step {
        progress.step
    }

    /// Continues from the progress saved in `store`.
    init(launcher: GoldenAppleLauncher, store: OnboardingProgressStore) {
        self.launcher = launcher
        self.store = store
        progress = store.load()
    }

    /// Changes the entered details and saves them.
    func update(_ change: (inout OnboardingProgress) -> Void) {
        var changed = progress
        change(&changed)
        guard changed != progress else {
            return
        }
        progress = changed
        store.save(changed)
    }

    func goToNextStep() {
        guard let next = step.next else {
            return
        }
        direction = .forward
        update { $0.step = next }
    }

    func goBack() {
        guard let previous = step.previous else {
            return
        }
        direction = .backward
        update { $0.step = previous }
    }

    /// Deletes the saved progress. Called when onboarding finishes.
    func discardProgress() {
        store.remove()
    }
}

#if DEBUG
extension OnboardingModel {
    /// A model for previews that saves to a temporary file, never to the real data folder.
    static func preview() -> OnboardingModel {
        let file = URL.temporaryDirectory.appending(path: "GoldenApple Onboarding Preview.json")
        return OnboardingModel(launcher: GoldenAppleLauncher(), store: OnboardingProgressStore(file: file))
    }
}
#endif
