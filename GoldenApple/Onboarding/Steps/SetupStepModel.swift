import Foundation
import Observation

/// Creates the chosen instance and downloads its game files.
/// A resumed or repeated setup reuses the instance it created before when that instance still matches the choices.
@MainActor
@Observable
final class SetupStepModel {
    enum Phase: Equatable {
        case working
        case failed
        case finished
    }

    private enum Weight {
        static let instance = 5
        static let downloads = 95
    }

    private let onboarding: OnboardingModel
    private(set) var phase = Phase.working
    private(set) var status = ""
    private(set) var progress = ProgressManager(totalCount: Weight.instance + Weight.downloads)
    private(set) var instance: Instance?
    private(set) var report: ErrorReport?

    init(onboarding: OnboardingModel) {
        self.onboarding = onboarding
    }

    private var launcher: GoldenAppleLauncher {
        onboarding.launcher
    }

    private var choices: OnboardingProgress {
        onboarding.progress
    }

    /// The choices as one line, such as `Fabric on Minecraft 1.21.4`.
    var summary: String {
        let version = choices.minecraftVersion ?? ""
        guard let loader = choices.loader else {
            return "Minecraft \(version)"
        }
        return "\(loader.displayName) on Minecraft \(version)"
    }

    /// Runs the whole setup. Cancelling the calling task stops it without an error.
    func run() async {
        phase = .working
        report = nil
        progress = ProgressManager(totalCount: Weight.instance + Weight.downloads)
        do {
            status = String(localized: "Creating your instance")
            let instance = try await preparedInstance()
            self.instance = instance
            progress.complete(count: Weight.instance)

            try await launcher.downloadGameFiles(
                for: instance,
                status: { text in
                    Task { @MainActor in self.showStatus(text) }
                },
                subprogress: progress.subprogress(assigningCount: Weight.downloads)
            )
            try Task.checkCancellation()
            status = String(localized: "Minecraft is ready")
            phase = .finished
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else {
                return
            }
            report = GoldenAppleLauncher.report(for: error, instance: instance)
            phase = .failed
        }
    }

    /// Status texts arrive on other tasks, so a late one must not replace the finished or failed text.
    private func showStatus(_ text: String) {
        if phase == .working {
            status = text
        }
    }

    /// The instance created earlier when it still matches the choices, else a new one.
    /// A created instance that no longer matches goes to the Trash.
    private func preparedInstance() async throws -> Instance {
        guard let minecraftVersion = choices.minecraftVersion else {
            throw LauncherError.missingMinecraftComponent(choices.effectiveInstanceName)
        }
        let name = choices.effectiveInstanceName

        if let existing = try await createdInstance() {
            if matchesChoices(existing, minecraftVersion: minecraftVersion) {
                guard existing.name != name else {
                    return existing
                }
                return try await launcher.renameInstance(existing, to: name)
            }
            try await launcher.deleteInstance(existing)
        }

        let created = try await launcher.createInstance(
            name: name,
            minecraftVersion: minecraftVersion,
            loader: choices.loader,
            loaderVersion: choices.loaderVersion
        )
        onboarding.update { $0.createdInstanceID = created.id }
        return created
    }

    private func createdInstance() async throws -> Instance? {
        guard let id = choices.createdInstanceID else {
            return nil
        }
        return try await launcher.instances().first { $0.id == id }
    }

    private func matchesChoices(_ instance: Instance, minecraftVersion: String) -> Bool {
        guard instance.minecraftVersion == minecraftVersion, instance.loader == choices.loader else {
            return false
        }
        guard let loaderVersion = choices.loaderVersion else {
            return true
        }
        return instance.loaderVersion == loaderVersion
    }
}
