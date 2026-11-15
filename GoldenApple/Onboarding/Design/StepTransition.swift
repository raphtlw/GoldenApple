import SwiftUI

/// Moves a step in from the side it comes from and out to the other side, with a short blur.
/// With Reduce Motion on, the step only fades.
struct StepTransition: Transition {
    let direction: OnboardingModel.Direction
    let reduceMotion: Bool

    private static let distance: CGFloat = 40
    private static let blurRadius: CGFloat = 8

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: reduceMotion ? 0 : offset(for: phase))
            .blur(radius: phase.isIdentity || reduceMotion ? 0 : Self.blurRadius)
    }

    private func offset(for phase: TransitionPhase) -> CGFloat {
        let sign: CGFloat = direction == .forward ? 1 : -1
        switch phase {
        case .willAppear:
            return Self.distance * sign
        case .didDisappear:
            return -Self.distance * sign
        case .identity:
            return 0
        }
    }
}
