import AppKit
import SwiftUI

struct WelcomeStep: View {
    let model: OnboardingModel

    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            AppIconHero()
                .reveal(isRevealed, order: 0)
                .padding(.bottom, 28)

            Text("Welcome to GoldenApple")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .reveal(isRevealed, order: 1)
                .padding(.bottom, 8)

            Text("A native Minecraft launcher for your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .reveal(isRevealed, order: 2)
                .padding(.bottom, 36)

            GlassEffectContainer(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(WelcomeFeature.all.enumerated()), id: \.element.symbol) { index, feature in
                        WelcomeFeatureCard(feature: feature)
                            .reveal(isRevealed, order: 3 + index)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 48)

            Spacer(minLength: 0)

            Button(action: model.goToNextStep) {
                Label("Get Started", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .reveal(isRevealed, order: 6)
        }
        .multilineTextAlignment(.center)
        .onAppear { isRevealed = true }
    }
}

/// The app icon with a soft amber glow behind it.
private struct AppIconHero: View {
    private static let iconSize: CGFloat = 128

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background {
                Circle()
                    .fill(OnboardingPalette.amber.gradient)
                    .frame(width: Self.iconSize * 0.9, height: Self.iconSize * 0.9)
                    .blur(radius: 40)
                    .opacity(0.55)
            }
            .shadow(color: OnboardingPalette.ember.opacity(0.25), radius: 16, y: 10)
            .accessibilityHidden(true)
    }
}

private struct WelcomeFeature {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    static let all = [
        WelcomeFeature(
            symbol: "square.stack.3d.up.fill",
            title: "Every version",
            detail: "Play anything from 1.6.1 to the newest release, each in its own instance."
        ),
        WelcomeFeature(
            symbol: "puzzlepiece.extension.fill",
            title: "Mods built in",
            detail: "Fabric, Quilt, Forge and NeoForge, with mods and modpacks from Modrinth and CurseForge."
        ),
        WelcomeFeature(
            symbol: "cup.and.heat.waves.fill",
            title: "Java sorted",
            detail: "GoldenApple picks or downloads the right Java for each version."
        ),
    ]
}

private struct WelcomeFeatureCard: View {
    let feature: WelcomeFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: feature.symbol)
                .font(.title2)
                .foregroundStyle(OnboardingPalette.amber.gradient)
                .frame(height: 28)
            Text(feature.title)
                .font(.headline)
            Text(feature.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeStep(model: .preview())
        .frame(width: 760, height: 660)
        .padding(.vertical, 40)
        .background(OnboardingBackground())
}
