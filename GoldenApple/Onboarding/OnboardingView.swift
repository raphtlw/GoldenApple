import SwiftUI

struct OnboardingView: View {
    @State private var model: OnboardingModel
    let onFinish: () -> Void

    init(launcher: GoldenAppleLauncher, onFinish: @escaping () -> Void) {
        _model = State(initialValue: OnboardingModel(launcher: launcher))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack {
            switch model.step {
            case .welcome:
                WelcomeStep(model: model)
            case .account:
                AccountStep(model: model)
            case .instance:
                InstanceStep(model: model)
            case .setup:
                SetupStep(model: model)
            case .finished:
                FinishedStep(model: model, onFinish: onFinish)
            }
        }
        .frame(width: 640, height: 540)
    }
}

/// Step views. Launcher APIs each step can use:
/// - Account: `launcher.microsoftClientID()`, `launcher.signInWithMicrosoft()`, `launcher.signInWithDeviceCode(onCode:)`,
///   `launcher.setDefaultAccount(_:)`
/// - Instance: `launcher.minecraftVersions(includeSnapshots:)`, `launcher.loaderVersions(_:minecraftVersion:)`
/// - Setup: `launcher.createInstance(name:minecraftVersion:loader:loaderVersion:)`,
///   `launcher.installEssential(into:subprogress:)`

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        Button("Continue", action: model.goToNextStep)
    }
}

private struct AccountStep: View {
    let model: OnboardingModel

    var body: some View {
        Button("Continue", action: model.goToNextStep)
    }
}

private struct InstanceStep: View {
    let model: OnboardingModel

    var body: some View {
        Button("Continue", action: model.goToNextStep)
    }
}

private struct SetupStep: View {
    let model: OnboardingModel

    var body: some View {
        Button("Continue", action: model.goToNextStep)
    }
}

private struct FinishedStep: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        Button("Done", action: onFinish)
    }
}

#Preview {
    OnboardingView(launcher: GoldenAppleLauncher(), onFinish: {})
}
