import AppKit
import SwiftUI

struct AccountStep: View {
    let model: OnboardingModel

    @State private var account: AccountStepModel

    init(model: OnboardingModel) {
        self.model = model
        _account = State(initialValue: AccountStepModel(launcher: model.launcher))
    }

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.crop.circle.badge.checkmark",
            title: "Sign in to Minecraft",
            subtitle: "Use the Microsoft account you bought Minecraft with. GoldenApple keeps the sign-in in your Keychain."
        ) {
            VStack(spacing: 16) {
                if let signedIn = account.account {
                    AccountCard(account: signedIn)
                        .transition(.blurReplace)
                } else if case .waitingForDeviceCode(let code) = account.activity {
                    DeviceCodePanel(code: code, onCancel: account.cancelSignIn)
                        .transition(.blurReplace)
                } else {
                    SignInOptions(account: account)
                        .transition(.blurReplace)
                }

                if let message = account.errorMessage {
                    OnboardingErrorBanner(message: message)
                }
            }
            .frame(maxWidth: 440)
            .animation(.smooth(duration: 0.35), value: account.account)
            .animation(.smooth(duration: 0.35), value: account.activity)
            .animation(.smooth(duration: 0.35), value: account.errorMessage)
        } actions: {
            OnboardingBackButton(model: model)
            Spacer()
            if account.account != nil {
                Button("Use Another Account", action: account.chooseAnotherAccount)
                    .buttonStyle(.glass)
                OnboardingContinueButton(action: model.goToNextStep)
            } else {
                Button("Set Up Later", action: model.goToNextStep)
                    .buttonStyle(.glass)
                    .disabled(account.isBusy)
            }
        }
        .task { await account.load() }
        .onDisappear(perform: account.cancelSignIn)
    }
}

private struct SignInOptions: View {
    @Bindable var account: AccountStepModel

    var body: some View {
        VStack(spacing: 12) {
            Button(action: account.signInWithBrowser) {
                HStack(spacing: 10) {
                    if account.activity == .signingInWithBrowser {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "globe")
                    }
                    Text("Sign In with Microsoft")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)

            Button(action: account.signInWithDeviceCode) {
                Label("Sign In with a Code", systemImage: "number")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if account.canAddOfflineAccounts {
                OfflineAccountForm(account: account)
                    .padding(.top, 8)
            }
        }
        .disabled(account.isBusy)
    }
}

/// A player name for an offline account. Debug builds always show it. Release builds show it after a Microsoft sign-in.
private struct OfflineAccountForm: View {
    @Bindable var account: AccountStepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or play offline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Player name", text: $account.offlineName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .onSubmit(account.addOfflineAccount)
                Button("Add", action: account.addOfflineAccount)
                    .buttonStyle(.glass)
                    .disabled(!account.isOfflineNameValid)
            }
            if !account.offlineName.isEmpty && !account.isOfflineNameValid {
                Text("Use 1 to 16 letters, digits or underscores.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct DeviceCodePanel: View {
    let code: DeviceCode?
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            if let code {
                Text("Enter this code on the Microsoft page")
                    .font(.headline)
                Text(code.userCode)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
                Button {
                    copyAndOpen(code)
                } label: {
                    Label("Copy Code and Open Page", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Waiting for you to finish. The code expires in")
                    Text(timerInterval: Date.now...code.expiresAt, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ProgressView("Asking Microsoft for a code")
            }
            Button("Cancel", action: onCancel)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func copyAndOpen(_ code: DeviceCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        openURL(code.verificationURL)
    }
}

private struct AccountCard: View {
    let account: Account

    var body: some View {
        HStack(spacing: 14) {
            Text(String(account.profileName.prefix(1)).uppercased())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(OnboardingPalette.amber.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.profileName)
                    .font(.title3.weight(.semibold))
                Text(account.kind == .microsoft ? "Microsoft account" : "Offline account")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var warning: LocalizedStringKey? {
        if account.needsSignIn {
            return "Sign in again to play online."
        }
        if account.kind == .microsoft && !account.ownsMinecraft {
            return "This account does not own Minecraft: Java Edition."
        }
        return nil
    }
}

#Preview {
    AccountStep(model: .preview())
        .frame(width: 760, height: 620)
        .background(OnboardingBackground())
}
