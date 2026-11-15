import SwiftUI

struct FinishedStep: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    @State private var account: Account?
    @State private var instance: Instance?
    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(.white, OnboardingPalette.amber.gradient)
                .symbolEffect(.bounce, value: isRevealed)
                .shadow(color: OnboardingPalette.amber.opacity(0.4), radius: 24, y: 8)
                .reveal(isRevealed, order: 0)
                .padding(.bottom, 24)

            Text("You're all set")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .reveal(isRevealed, order: 1)
                .padding(.bottom, 8)

            Text("GoldenApple is ready to play.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .reveal(isRevealed, order: 2)
                .padding(.bottom, 32)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    SummaryTile(
                        symbol: "person.crop.circle.fill",
                        title: "Account",
                        value: account?.profileName ?? String(localized: "Not signed in"),
                        detail: accountDetail
                    )
                    SummaryTile(
                        symbol: "square.stack.3d.up.fill",
                        title: "Instance",
                        value: instance?.name ?? String(localized: "None yet"),
                        detail: instanceDetail
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)
            .reveal(isRevealed, order: 3)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                OnboardingBackButton(model: model)
                Spacer()
                OnboardingContinueButton(title: "Open GoldenApple", action: onFinish)
            }
            .controlSize(.large)
            .reveal(isRevealed, order: 4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 56)
        .task {
            await load()
            isRevealed = true
        }
    }

    private var accountDetail: String {
        guard let account else {
            return String(localized: "Sign in from the launcher at any time")
        }
        return account.kind == .microsoft ? String(localized: "Microsoft account") : String(localized: "Offline account")
    }

    private var instanceDetail: String {
        guard let instance else {
            return String(localized: "Create one from the launcher")
        }
        guard let loader = instance.loader else {
            return "Minecraft \(instance.minecraftVersion)"
        }
        return "\(loader.displayName) on Minecraft \(instance.minecraftVersion)"
    }

    private func load() async {
        account = await model.launcher.defaultAccount()
        if let id = model.progress.createdInstanceID {
            instance = try? await model.launcher.instances().first { $0.id == id }
        }
    }
}

private struct SummaryTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(OnboardingPalette.amber.gradient)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FinishedStep(model: .preview(), onFinish: {})
        .frame(width: 760, height: 620)
        .background(OnboardingBackground())
}
