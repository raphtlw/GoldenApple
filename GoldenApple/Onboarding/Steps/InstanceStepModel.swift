import Foundation
import Observation

/// Loads the Minecraft versions and checks that the chosen loader exists for the chosen version.
/// The choices themselves are stored in the onboarding progress.
@MainActor
@Observable
final class InstanceStepModel {
    enum LoaderAvailability: Equatable {
        case notNeeded
        case checking
        /// The recommended version, which the setup step installs.
        case available(version: String)
        case unavailable
        case failed(String)
    }

    /// A loader choice and its version, used to restart the loader check when either changes.
    struct LoaderQuery: Equatable {
        let minecraftVersion: String?
        let loader: ModLoader?
    }

    private let onboarding: OnboardingModel
    private(set) var versions: [GameVersion] = []
    private(set) var isLoadingVersions = false
    private(set) var versionsError: String?
    private(set) var loaderAvailability = LoaderAvailability.notNeeded
    private(set) var includesSnapshots: Bool

    init(onboarding: OnboardingModel) {
        self.onboarding = onboarding
        includesSnapshots = false
    }

    private var progress: OnboardingProgress {
        onboarding.progress
    }

    var loaderQuery: LoaderQuery {
        LoaderQuery(minecraftVersion: progress.minecraftVersion, loader: progress.loader)
    }

    var defaultInstanceName: String {
        progress.defaultInstanceName
    }

    var isInstanceNameUsable: Bool {
        FileSystem.safeFolderName(progress.effectiveInstanceName) != nil
    }

    var canContinue: Bool {
        guard progress.minecraftVersion != nil, isInstanceNameUsable else {
            return false
        }
        switch loaderAvailability {
        case .notNeeded, .available:
            return true
        case .checking, .unavailable, .failed:
            return false
        }
    }

    /// Loads the version list. A saved snapshot choice turns on snapshots first, so it stays in the list.
    func loadVersions() async {
        if let saved = progress.minecraftVersion, versions.isEmpty {
            let releases = try? await onboarding.launcher.minecraftVersions(includeSnapshots: false)
            if let releases, !releases.contains(where: { $0.id == saved }) {
                includesSnapshots = true
            }
        }
        await reloadVersions()
    }

    func setIncludesSnapshots(_ includesSnapshots: Bool) async {
        self.includesSnapshots = includesSnapshots
        await reloadVersions()
    }

    func selectMinecraftVersion(_ version: String) {
        onboarding.update { $0.minecraftVersion = version }
    }

    func selectLoader(_ loader: ModLoader?) {
        onboarding.update { $0.loader = loader }
    }

    func setInstanceName(_ name: String) {
        onboarding.update { $0.instanceName = name.isEmpty ? nil : name }
    }

    /// Checks the loader of `loaderQuery`. Runs again from the view whenever the query changes.
    func checkLoader() async {
        guard let loader = progress.loader, let minecraftVersion = progress.minecraftVersion else {
            loaderAvailability = .notNeeded
            return
        }
        loaderAvailability = .checking
        do {
            let loaderVersions = try await onboarding.launcher.loaderVersions(loader, minecraftVersion: minecraftVersion)
            guard !Task.isCancelled else {
                return
            }
            if let chosen = loaderVersions.first(where: \.isRecommended) ?? loaderVersions.first {
                loaderAvailability = .available(version: chosen.version)
            } else {
                loaderAvailability = .unavailable
            }
        } catch {
            if !Task.isCancelled {
                loaderAvailability = .failed(error.localizedDescription)
            }
        }
    }

    private func reloadVersions() async {
        isLoadingVersions = true
        versionsError = nil
        defer { isLoadingVersions = false }
        do {
            versions = try await onboarding.launcher.minecraftVersions(includeSnapshots: includesSnapshots)
            selectNewestReleaseIfNeeded()
        } catch {
            versionsError = error.localizedDescription
        }
    }

    /// Keeps the saved version when the list has it, else picks the newest release.
    private func selectNewestReleaseIfNeeded() {
        if let saved = progress.minecraftVersion, versions.contains(where: { $0.id == saved }) {
            return
        }
        if let newest = versions.first(where: { $0.type == "release" }) ?? versions.first {
            selectMinecraftVersion(newest.id)
        }
    }
}
