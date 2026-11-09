import Foundation

/// An error as plain text for a bug report. The app shows `title` and `message`, and copies `text`.
/// Access tokens, session values and profile IDs of earlier launches are censored in every field.
nonisolated struct ErrorReport: Sendable {
    /// `details` has at most this many lines.
    static let detailLineLimit = 200

    let title: String
    let message: String
    /// More lines for the report, such as the installer stack trace or the end of a log file.
    let details: String?
    /// The title, the message, the details and the context, ready for the pasteboard.
    let text: String

    init(error: any Error, instance: Instance?, configuration: GoldenAppleConfiguration = .default) {
        let censor = LogCensor.forLaunchSecrets()
        let launcherError = error as? LauncherError
        let isCancellation = error is CancellationError
        title = censor.censorIncludingTokenShapes(launcherError?.title ?? (isCancellation ? "Cancelled" : "Unexpected error"))
        message = censor.censorIncludingTokenShapes(isCancellation ? "The task was cancelled." : error.localizedDescription)
        let detailLines = launcherError.flatMap { Self.detailLines(for: $0, instance: instance) } ?? []
        details = detailLines.isEmpty ? nil : censor.censorIncludingTokenShapes(detailLines.suffix(Self.detailLineLimit).joined(separator: "\n"))

        var sections = [title, message]
        if let details {
            sections.append("Details:\n\(details)")
        }
        sections.append("Context:\n" + Self.contextLines(instance: instance, configuration: configuration).joined(separator: "\n"))
        text = censor.censorIncludingTokenShapes(sections.joined(separator: "\n\n"))
    }

    // MARK: Details

    private static func detailLines(for error: LauncherError, instance: Instance?) -> [String]? {
        switch error {
        case .forgeInstallerFailed(_, _, _, _, let stackTrace, let logFile):
            if !stackTrace.isEmpty {
                return stackTrace
            }
            return LaunchLogFile.tail(of: URL(filePath: logFile), limit: detailLineLimit)
        case .gameCrashed:
            return instance.flatMap { LaunchLogFile.tail(of: $0.paths.logFile(.latestLaunch), limit: detailLineLimit) }
        case .downloadsFailed(let failures):
            return failures.map { "\($0.url.absoluteString) → \($0.destination.path): \($0.reason)" }
        case .filesMissingOffline(let files):
            return files
        default:
            return nil
        }
    }

    // MARK: Context

    private static func contextLines(instance: Instance?, configuration: GoldenAppleConfiguration) -> [String] {
        var lines = [
            "GoldenApple: \(configuration.launcherVersion)",
            "macOS: \(macOSVersion)",
        ]
        guard let instance else {
            return lines
        }
        lines.append("Instance: \(instance.name)")
        lines.append("Minecraft: \(instance.minecraftVersion)")
        if let loader = instance.loader {
            lines.append("Loader: \(loader.displayName) \(instance.loaderVersion ?? "")")
        }
        if let java = lastCheckedJava(of: instance) {
            lines.append("Java: \(java.version) (\(java.vendor)) at \(java.path)")
        }
        return lines
    }

    /// `27.2 (Build 27C5045)` from `Version 27.2 (Build 27C5045)`.
    private static var macOSVersion: String {
        let text = ProcessInfo.processInfo.operatingSystemVersionString
        return text.hasPrefix("Version ") ? String(text.dropFirst("Version ".count)) : text
    }

    /// The Java that the last launch of the instance checked and used, from `Instance.json`.
    private static func lastCheckedJava(of instance: Instance) -> JavaCheckResult? {
        let configuration = try? JSONFiles.readOwnFile(InstanceConfiguration.self, from: instance.paths.configurationFile)
        return configuration?.javaCheck?.result
    }
}
