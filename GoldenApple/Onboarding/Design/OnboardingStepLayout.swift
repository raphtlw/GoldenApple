import SwiftUI

/// The frame of every step after the welcome step: a header with a symbol, a title and a subtitle,
/// the step content, and a row of actions at the bottom. The parts reveal one after another.
struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.amber.gradient)
                    .frame(height: 38)
                    .reveal(isRevealed, order: 0)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .reveal(isRevealed, order: 1)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(isRevealed, order: 2)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .reveal(isRevealed, order: 3)

            HStack(spacing: 12) {
                actions
            }
            .controlSize(.large)
            .reveal(isRevealed, order: 4)
        }
        .padding(.horizontal, 56)
        .onAppear { isRevealed = true }
    }
}

struct OnboardingBackButton: View {
    let model: OnboardingModel

    var body: some View {
        Button(action: model.goBack) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.glass)
    }
}

/// A primary button with the arrow after the title. Return presses it.
struct OnboardingContinueButton: View {
    var title: LocalizedStringKey = "Continue"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
    }
}

/// A red-tinted glass panel with an error message.
struct OnboardingErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(.red.opacity(0.12)), in: .rect(cornerRadius: 16))
        .transition(.blurReplace)
    }
}

/// Puts the icon after the title, for buttons that move forward.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}
