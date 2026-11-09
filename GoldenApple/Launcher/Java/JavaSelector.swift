import Foundation
import os

/// Chooses the Java binary for a launch, downloading a runtime when needed.
nonisolated struct JavaSelector: Sendable {
    let paths: LauncherPaths
    let settings: SettingsStore
    let metadata: MetadataClient
    let installer: JavaRuntimeInstaller
    let discovery: JavaDiscovery
    let instances: InstanceStore

    /// Picks Java for `profile`. The check result is cached in the instance's `Instance.json`.
    /// Offline, no runtime is downloaded.
    func selectJava(
        for profile: LaunchProfile,
        instance: Instance,
        mode: MetadataMode,
        subprogress: consuming Subprogress? = nil
    ) async throws -> JavaInstallation {
        let current = settings.current
        guard current.automaticJava else {
            return try await configuredJava(current.javaPath, for: profile, instance: instance)
        }
        let majors = profile.compatibleJavaMajors

        if let name = profile.compatibleJavaName {
            let binary = paths.javaRuntime(name).appending(path: "bin/java")
            if let installation = await check(binary, instance: instance), Self.isCompatible(installation, with: majors) {
                return installation
            }
        }

        if mode == .online, let download = try await downloadableRuntime(for: profile) {
            let binary = try await installer.install(download.runtime, folderName: download.folderName, subprogress: subprogress)
            guard let installation = await check(binary, instance: instance) else {
                throw LauncherError.javaUnusable(binary.path)
            }
            return installation
        }

        let installed = await discovery.installations()
        if let installation = installed.first(where: { Self.isCompatible($0, with: majors) }) {
            return installation
        }
        throw LauncherError.noCompatibleJava(majors)
    }

    /// The Java binary from settings, used when automatic Java is off.
    private func configuredJava(_ javaPath: String?, for profile: LaunchProfile, instance: Instance) async throws -> JavaInstallation {
        guard let javaPath = javaPath.nonEmpty else {
            throw LauncherError.javaPathNotSet
        }
        guard let installation = await check(URL(filePath: javaPath), instance: instance) else {
            throw LauncherError.javaUnusable(javaPath)
        }
        guard Self.isCompatible(installation, with: profile.compatibleJavaMajors) else {
            throw LauncherError.javaIncompatible(path: javaPath, major: installation.major, compatible: profile.compatibleJavaMajors)
        }
        return installation
    }

    /// For each compatible major, the `net.minecraft.java` document `java<major>`: a `mac-os-arm64` runtime
    /// named `compatibleJavaName`, else any `mac-os-arm64` runtime in that document.
    private func downloadableRuntime(for profile: LaunchProfile) async throws -> (runtime: JavaRuntime, folderName: String)? {
        for major in profile.compatibleJavaMajors {
            let document: VersionDocument
            do {
                document = try await metadata.versionDocument(ComponentID.mojangJava, version: "java\(major)", mode: .online)
            } catch LauncherError.unknownVersion {
                continue
            }
            let candidates = document.runtimes.filter { $0.runtimeOS == JavaRuntime.macOSARM64 }
            let runtime = candidates.first { $0.name == profile.compatibleJavaName } ?? candidates.first
            if let runtime {
                return (runtime, profile.compatibleJavaName ?? runtime.name)
            }
        }
        return nil
    }

    /// Checks a binary, reusing and updating the cached check in `Instance.json`. Only `aarch64` Java counts.
    private func check(_ binary: URL, instance: Instance) async -> JavaInstallation? {
        let cached = try? instances.configuration(of: instance).javaCheck
        guard let checked = await JavaChecker.check(binary, cached: cached), checked.result.isARM64 else {
            return nil
        }
        if checked.record != cached {
            do {
                try instances.updateConfiguration(of: instance) { $0.javaCheck = checked.record }
            } catch {
                LauncherLog.java.error("Could not save the Java check: \(error.localizedDescription, privacy: .public)")
            }
        }
        return checked.result.installation
    }

    private static func isCompatible(_ installation: JavaInstallation, with majors: [Int]) -> Bool {
        majors.isEmpty || majors.contains(installation.major)
    }
}
