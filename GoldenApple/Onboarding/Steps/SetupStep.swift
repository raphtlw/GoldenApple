import AppKit
import SwiftUI

struct SetupStep: View {
    let model: OnboardingModel

    @State private var setup: SetupStepModel
    @State private var attempt = 0

    /// How long the finished ring stays on screen before the next step.
    private static let finishedPause = Duration.milliseconds(900)

    init(model: OnboardingModel) {
        self.model = model
        _setup = State(initialValue: SetupStepModel(onboarding: model))
    }

    var body: some View {
        OnboardingStepLayout(
            symbol: "arrow.down.circle.fill",
            title: "Getting Minecraft ready",
            subtitle: "GoldenApple downloads the game, Java and assets now, so your first launch does not wait for them."
        ) {
            VStack(spacing: 18) {
                ProgressRing(fraction: setup.progress.fractionCompleted, phase: setup.phase)
                VStack(spacing: 4) {
                    Text(setup.summary)
                        .font(.headline)
                    Text(setup.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(.smooth(duration: 0.25), value: setup.status)
                }
                if setup.phase == .failed, let report = setup.report {
                    SetupFailure(report: report)
                }
            }
            .frame(maxWidth: 480)
            .animation(.smooth(duration: 0.35), value: setup.phase)
        } actions: {
            OnboardingBackButton(model: model)
            Spacer()
            if setup.phase == .failed {
                if setup.instance != nil {
                    Button("Download Later", action: model.goToNextStep)
                        .buttonStyle(.glass)
                }
                Button {
                    attempt += 1
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .task(id: attempt) {
            await setup.run()
            guard setup.phase == .finished else {
                return
            }
            try? await Task.sleep(for: Self.finishedPause)
            if !Task.isCancelled {
                model.goToNextStep()
            }
        }
    }
}

/// A ring that fills with the progress and turns into a checkmark when setup finishes.
private struct ProgressRing: View {
    let fraction: Double
    let phase: SetupStepModel.Phase

    private static let size: CGFloat = 128
    private static let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [OnboardingPalette.gold, OnboardingPalette.amber, OnboardingPalette.ember], center: .center),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: fraction)
            center
                .transition(.blurReplace)
        }
        .frame(width: Self.size, height: Self.size)
        .padding(Self.lineWidth / 2)
        .glassEffect(.regular, in: .circle)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }

    @ViewBuilder
    private var center: some View {
        switch phase {
        case .working:
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: fraction))
                .animation(.smooth(duration: 0.3), value: fraction)
        case .finished:
            Image(systemName: "checkmark")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(OnboardingPalette.amber.gradient)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }
}

private struct SetupFailure: View {
    let report: ErrorReport

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report.title)
                .font(.headline)
            Text(report.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(6)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.text, forType: .string)
                didCopy = true
            } label: {
                Label(didCopy ? "Copied" : "Copy Report", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(.red.opacity(0.1)), in: .rect(cornerRadius: 18))
        .transition(.blurReplace)
    }
}

#Preview {
    SetupStep(model: .preview())
        .frame(width: 760, height: 620)
        .background(OnboardingBackground())
}
