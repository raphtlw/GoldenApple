import Foundation
import os

/// Sends censored log lines and status messages of one launch as events, and writes every line to
/// `Latest Launch.log` when `file` is set. Launcher lines are also written to `os.Logger`.
nonisolated struct LaunchLog: Sendable {
    private static let launcherLinePrefix = "[GoldenApple] "

    let censor: LogCensor
    let send: @Sendable (LaunchEvent) -> Void
    var file: LaunchLogFile?

    func status(_ text: String) {
        send(.status(censor.censor(text)))
        launcher(text)
    }

    func launcher(_ text: String, level: LogLine.Level = .info) {
        let censored = censor.censor(text)
        LauncherLog.launch.log(level: level.osLogType, "\(censored, privacy: .public)")
        file?.write(Self.launcherLinePrefix + censored)
        send(.log(LogLine(text: censored, level: level, source: .launcher, date: Date())))
    }

    /// One line of game output. During a Forge or NeoForge launch, `installer` decides the source of the line.
    func game(_ text: String, isStandardError: Bool, installer: ForgeInstallerMonitor? = nil) {
        let censored = censor.censor(text)
        let source = installer?.source(of: censored) ?? .game
        file?.write(censored)
        let level: LogLine.Level = source == .diagnostic ? .debug : GameLogLevel.detect(in: censored) ?? (isStandardError ? .warning : .info)
        send(.log(LogLine(text: censored, level: level, source: source, date: Date())))
    }

    /// Opens a log file of the launch. A file that cannot be created is reported as a warning and skipped.
    func openFile(_ url: URL) -> LaunchLogFile? {
        do {
            return try LaunchLogFile(replacing: url)
        } catch {
            launcher("Could not create \(url.path): \(error.localizedDescription)", level: .warning)
            return nil
        }
    }
}

/// Finds the log level marker of a game line, such as `[Render thread/WARN]`.
nonisolated enum GameLogLevel {
    private static let markers: [(marker: String, level: LogLine.Level)] = [
        ("/FATAL]", .fatal),
        ("/ERROR]", .error),
        ("/WARN]", .warning),
        ("/INFO]", .info),
        ("/DEBUG]", .debug),
        ("/TRACE]", .debug),
    ]

    /// The level of the first marker in the line, or nil when the line has none.
    static func detect(in line: String) -> LogLine.Level? {
        markers
            .compactMap { entry in line.range(of: entry.marker).map { (position: $0.lowerBound, level: entry.level) } }
            .min { $0.position < $1.position }?
            .level
    }
}

nonisolated extension LogLine.Level {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        case .fatal: .fault
        }
    }
}
