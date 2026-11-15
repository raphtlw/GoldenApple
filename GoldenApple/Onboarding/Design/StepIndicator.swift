import SwiftUI

/// A row of capsules. The current step is a wide amber capsule, the steps before it are filled and the steps after it are faint.
struct StepIndicator: View {
    let current: Int
    let count: Int

    private static let dotSize: CGFloat = 7
    private static let activeWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: index == current ? Self.activeWidth : Self.dotSize, height: Self.dotSize)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }

    private func fill(for index: Int) -> AnyShapeStyle {
        if index == current {
            return AnyShapeStyle(OnboardingPalette.amber)
        }
        if index < current {
            return AnyShapeStyle(OnboardingPalette.amber.opacity(0.45))
        }
        return AnyShapeStyle(.secondary.opacity(0.35))
    }
}

#Preview {
    StepIndicator(current: 1, count: 5)
        .padding()
}
