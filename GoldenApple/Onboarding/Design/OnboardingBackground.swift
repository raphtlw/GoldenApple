import SwiftUI

/// A warm mesh gradient behind every onboarding step. The center points drift slowly unless Reduce Motion is on.
struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let driftPeriod = 24.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / Self.driftPeriod * 2 * .pi
            MeshGradient(width: 3, height: 3, points: points(phase: phase), colors: colors)
        }
        .ignoresSafeArea()
    }

    private func points(phase: Double) -> [SIMD2<Float>] {
        let drift = Float(0.06)
        let x = Float(sin(phase)) * drift
        let y = Float(cos(phase)) * drift
        return [
            [0, 0], [0.5 + x, 0], [1, 0],
            [0, 0.5 - y], [0.5 + x, 0.45 + y], [1, 0.5 + y],
            [0, 1], [0.5 - x, 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        colorScheme == .dark ? Self.darkColors : Self.lightColors
    }

    private static let lightColors: [Color] = [
        Color(red: 1.00, green: 0.97, blue: 0.93), Color(red: 1.00, green: 0.93, blue: 0.83), Color(red: 1.00, green: 0.96, blue: 0.90),
        Color(red: 1.00, green: 0.90, blue: 0.76), OnboardingPalette.honey.opacity(0.85), Color(red: 1.00, green: 0.92, blue: 0.80),
        Color(red: 1.00, green: 0.95, blue: 0.88), Color(red: 1.00, green: 0.88, blue: 0.72), Color(red: 1.00, green: 0.97, blue: 0.92),
    ]

    private static let darkColors: [Color] = [
        Color(red: 0.07, green: 0.04, blue: 0.02), Color(red: 0.13, green: 0.06, blue: 0.02), Color(red: 0.08, green: 0.04, blue: 0.02),
        Color(red: 0.16, green: 0.07, blue: 0.02), Color(red: 0.36, green: 0.15, blue: 0.03), Color(red: 0.14, green: 0.06, blue: 0.02),
        Color(red: 0.06, green: 0.03, blue: 0.01), Color(red: 0.18, green: 0.08, blue: 0.02), Color(red: 0.07, green: 0.03, blue: 0.01),
    ]
}

#Preview {
    OnboardingBackground()
        .frame(width: 760, height: 660)
}
