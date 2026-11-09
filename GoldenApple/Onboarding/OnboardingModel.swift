import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome
        case account
        case instance
        case setup
        case finished
    }

    let launcher: GoldenAppleLauncher
    private(set) var step = Step.welcome

    init(launcher: GoldenAppleLauncher) {
        self.launcher = launcher
    }

    func goToNextStep() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) {
            step = previous
        }
    }
}
