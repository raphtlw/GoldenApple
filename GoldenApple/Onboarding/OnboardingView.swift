import SwiftUI

struct OnboardingView: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                currentStep
                    .id(model.step)
                    .transition(StepTransition(direction: model.direction, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.45), value: model.step)

            StepIndicator(current: model.step.index, count: OnboardingModel.Step.allCases.count)
                .padding(.top, 28)
        }
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 760, height: 660)
        .tint(OnboardingPalette.amber)
        .background {
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents()
        }
        .containerBackground(for: .window) {
            OnboardingBackground()
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private var currentStep: some View {
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
}

#Preview {
    OnboardingView(model: .preview(), onFinish: {})
}
