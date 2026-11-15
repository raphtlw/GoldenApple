import SwiftUI

extension View {
    /// Fades and lifts the view in when `isRevealed` becomes true. Higher `order` values start later, for a stagger.
    func reveal(_ isRevealed: Bool, order: Int) -> some View {
        modifier(RevealModifier(isRevealed: isRevealed, order: order))
    }
}

private struct RevealModifier: ViewModifier {
    let isRevealed: Bool
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stagger = 0.07
    private static let lift: CGFloat = 14
    private static let blurRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : Self.lift)
            .blur(radius: isRevealed || reduceMotion ? 0 : Self.blurRadius)
            .animation(.smooth(duration: 0.6).delay(Double(order) * Self.stagger), value: isRevealed)
    }
}
