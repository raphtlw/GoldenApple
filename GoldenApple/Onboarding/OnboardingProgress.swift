import Foundation
import os

/// Saved by name, so a saved file still opens the same step after steps are added or moved.
nonisolated enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case welcome
    case account
    case instance
    case setup
    case finished

    /// The position in the flow, starting at 0.
    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var next: OnboardingStep? {
        Self.allCases.indices.contains(index + 1) ? Self.allCases[index + 1] : nil
    }

    var previous: OnboardingStep? {
        index > 0 ? Self.allCases[index - 1] : nil
    }
}

/// The step and the details entered so far, stored in `Onboarding.json`.
/// The signed-in account is not part of it: the launcher already keeps it in `Accounts.json` and the Keychain.
nonisolated struct OnboardingProgress: Codable, Equatable, Sendable {
    var step = OnboardingStep.welcome
    var instanceName: String?
    var minecraftVersion: String?
    var loader: ModLoader?
    /// Nil means the recommended version of `loader`.
    var loaderVersion: String?
    /// The instance the setup step created, so a resumed setup does not create a second one.
    var createdInstanceID: String?

    init() {}

    /// The name used when the player leaves the name field empty, such as `Fabric 1.21.4`.
    var defaultInstanceName: String {
        let version = minecraftVersion ?? ""
        guard let loader else {
            return "Minecraft \(version)"
        }
        return "\(loader.displayName) \(version)"
    }

    /// The typed name, or `defaultInstanceName` when nothing was typed.
    var effectiveInstanceName: String {
        instanceName.nonEmpty ?? defaultInstanceName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decodeIfPresent(OnboardingStep.self, forKey: .step) ?? .welcome
        instanceName = try container.decodeIfPresent(String.self, forKey: .instanceName)
        minecraftVersion = try container.decodeIfPresent(String.self, forKey: .minecraftVersion)
        loader = try container.decodeIfPresent(ModLoader.self, forKey: .loader)
        loaderVersion = try container.decodeIfPresent(String.self, forKey: .loaderVersion)
        createdInstanceID = try container.decodeIfPresent(String.self, forKey: .createdInstanceID)
    }
}

/// Reads and writes `Onboarding.json`. A missing or unreadable file gives a fresh start at the welcome step.
/// Failures are logged and not thrown, because lost progress only means the player sees a step again.
nonisolated struct OnboardingProgressStore: Sendable {
    let file: URL

    func load() -> OnboardingProgress {
        guard FileSystem.exists(file) else {
            return OnboardingProgress()
        }
        do {
            return try JSONFiles.readOwnFile(OnboardingProgress.self, from: file)
        } catch {
            LauncherLog.general.error("Could not read onboarding progress, starting again: \(error.localizedDescription, privacy: .public)")
            return OnboardingProgress()
        }
    }

    func save(_ progress: OnboardingProgress) {
        do {
            try JSONFiles.writeOwnFile(progress, to: file)
        } catch {
            LauncherLog.general.error("Could not save onboarding progress: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove() {
        do {
            try FileSystem.removeIfPresent(file)
        } catch {
            LauncherLog.general.error("Could not remove onboarding progress: \(error.localizedDescription, privacy: .public)")
        }
    }
}
