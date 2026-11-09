import Foundation
import Synchronization

/// User settings stored in `Settings.json`. Keys missing from the file decode to the defaults.
nonisolated struct LauncherSettings: Codable, Equatable, Sendable {
    var minimumMemoryMiB = 512
    var maximumMemoryMiB = LauncherSettings.defaultMaximumMemoryMiB
    var windowWidth = 854
    var windowHeight = 480
    /// Extra JVM arguments, split like a shell command line.
    var javaArguments = ""
    var environment: [String: String] = [:]
    /// Pick or download the right Java for each instance. When false, `javaPath` is used.
    var automaticJava = true
    var javaPath: String?
    var concurrentDownloads = 6
    var metadataURLOverride: String?
    var microsoftClientIDOverride: String?
    var curseForgeAPIKey: String?
    var onboardingCompleted = false

    init() {}

    /// Total RAM divided by 1.5 on Macs with less than 6 GiB, else 4 GiB.
    static var defaultMaximumMemoryMiB: Int {
        let memoryMiB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        return memoryMiB < 6 * 1024 ? Int(Double(memoryMiB) / 1.5) : 4096
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LauncherSettings()
        minimumMemoryMiB = try container.decodeIfPresent(Int.self, forKey: .minimumMemoryMiB) ?? defaults.minimumMemoryMiB
        maximumMemoryMiB = try container.decodeIfPresent(Int.self, forKey: .maximumMemoryMiB) ?? defaults.maximumMemoryMiB
        windowWidth = try container.decodeIfPresent(Int.self, forKey: .windowWidth) ?? defaults.windowWidth
        windowHeight = try container.decodeIfPresent(Int.self, forKey: .windowHeight) ?? defaults.windowHeight
        javaArguments = try container.decodeIfPresent(String.self, forKey: .javaArguments) ?? defaults.javaArguments
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? defaults.environment
        automaticJava = try container.decodeIfPresent(Bool.self, forKey: .automaticJava) ?? defaults.automaticJava
        javaPath = try container.decodeIfPresent(String.self, forKey: .javaPath)
        concurrentDownloads = try container.decodeIfPresent(Int.self, forKey: .concurrentDownloads) ?? defaults.concurrentDownloads
        metadataURLOverride = try container.decodeIfPresent(String.self, forKey: .metadataURLOverride)
        microsoftClientIDOverride = try container.decodeIfPresent(String.self, forKey: .microsoftClientIDOverride)
        curseForgeAPIKey = try container.decodeIfPresent(String.self, forKey: .curseForgeAPIKey)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
    }

    // MARK: Effective values

    func effectiveMicrosoftClientID(_ configuration: GoldenAppleConfiguration) -> String {
        microsoftClientIDOverride.nonEmpty ?? configuration.microsoftClientID
    }

    func effectiveCurseForgeAPIKey(_ configuration: GoldenAppleConfiguration) -> String {
        curseForgeAPIKey.nonEmpty ?? configuration.curseForgeAPIKey
    }

    func effectiveMetadataBaseURL(_ configuration: GoldenAppleConfiguration) -> URL {
        guard let override = metadataURLOverride.nonEmpty, let url = URL(string: override) else {
            return configuration.metadataBaseURL
        }
        return url
    }
}

/// Holds the current settings in memory and writes every change to `Settings.json`.
nonisolated final class SettingsStore: Sendable {
    private let file: URL
    private let state = Mutex(LauncherSettings())

    init(file: URL) {
        self.file = file
    }

    var current: LauncherSettings {
        state.withLock { $0 }
    }

    /// Reads `Settings.json`, or writes the defaults when the file does not exist.
    func load() throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            try JSONFiles.writeOwnFile(current, to: file)
            return
        }
        let settings = try JSONFiles.readOwnFile(LauncherSettings.self, from: file)
        state.withLock { $0 = settings }
    }

    func update(_ change: (inout LauncherSettings) -> Void) throws {
        try state.withLock { settings in
            var changed = settings
            change(&changed)
            try JSONFiles.writeOwnFile(changed, to: file)
            settings = changed
        }
    }
}
