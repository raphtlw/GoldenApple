import Foundation
import Synchronization

/// Why the Forge or NeoForge installer phase of a launch failed.
nonisolated enum ForgeInstallerFailureCause: Hashable, Sendable {
    /// A thread dump showed the installer waiting at its error dialog, which macOS cannot show here.
    case errorDialog
    /// The installer phase ran longer than the backstop.
    case timedOut
    /// The process exited before Minecraft started.
    case exited(code: Int32)
}

/// Watches the installer that ForgeWrapper runs inside the game process before Minecraft starts.
///
/// The installer phase starts with the process and ends at the first game log line. Its lines are tagged
/// `installer` and written to `Forge Installer.log`. When the installer is quiet for 20 seconds, the monitor asks
/// the JVM for a thread dump with `SIGQUIT`. A dump that shows the error dialog, or a phase longer than 15 minutes,
/// is a failure, and the monitor terminates the process.
nonisolated final class ForgeInstallerMonitor: Sendable {
    struct Failure: Sendable {
        let cause: ForgeInstallerFailureCause
        let stackTrace: [String]
    }

    /// What the watch loop does after one check.
    private enum Decision {
        case keepWaiting
        case phaseEnded
        case requestThreadDump
        case threadDumpShowedNoError
        case fail(ForgeInstallerFailureCause)
    }

    private struct State {
        var isInstallerPhase = true
        var phaseStart: ContinuousClock.Instant?
        var lastOutput: ContinuousClock.Instant?
        var isThreadDumpRequested = false
        var threadDump = ThreadDumpReader()
        /// Set when a dump is complete, until the watch loop acts on it.
        var completedDumpShowsError: Bool?
        var stackTraces = StackTraceCollector()
        var failureCause: ForgeInstallerFailureCause?
    }

    static let quietPeriod = Duration.seconds(20)
    static let backstop = Duration.seconds(15 * 60)
    private static let checkInterval = Duration.seconds(1)
    /// A dump arrives in one burst. A dump without its last line is complete after this much silence.
    private static let threadDumpSettleTime = Duration.seconds(2)

    static let threadDumpHeader = "--- Thread dump ---"
    static let threadDumpFooter = "--- End of thread dump ---"

    /// `Forge` or `NeoForge`, for log messages.
    let loaderName: String
    let logFileURL: URL
    private let logFile: LaunchLogFile?
    private let clock = ContinuousClock()
    private let state = Mutex(State())

    init(loaderName: String, logFileURL: URL, logFile: LaunchLogFile?) {
        self.loaderName = loaderName
        self.logFileURL = logFileURL
        self.logFile = logFile
    }

    /// Starts the clocks of the phase. Call it when the process has started.
    func begin() {
        let now = clock.now
        state.withLock { state in
            state.phaseStart = now
            state.lastOutput = now
        }
    }

    /// Tags one censored output line and writes installer phase lines to `Forge Installer.log`.
    func source(of line: String) -> LogLine.Source {
        let now = clock.now
        return state.withLock { state in
            state.lastOutput = now
            let wasReadingDump = state.threadDump.isReading
            let isDumpLine = state.threadDump.read(line, isExpectingDump: state.isThreadDumpRequested)
            if isDumpLine, !wasReadingDump {
                state.isThreadDumpRequested = false
                logFile?.write(Self.threadDumpHeader)
            }
            if isDumpLine {
                logFile?.write(line)
            }
            if wasReadingDump, !state.threadDump.isReading {
                completeThreadDump(&state)
            }
            if isDumpLine {
                return .diagnostic
            }
            guard state.isInstallerPhase else {
                return .game
            }
            if GameLogLine.matches(line) {
                state.isInstallerPhase = false
                logFile?.close()
                return .game
            }
            logFile?.write(line)
            state.stackTraces.add(line)
            return .installer
        }
    }

    /// Checks the installer once a second until the phase ends, the task is cancelled, or the installer failed.
    /// Thread dump requests go to `process`, and a failure terminates it.
    func watch(_ process: GameProcess, log: LaunchLog) async {
        while true {
            do {
                try await Task.sleep(for: Self.checkInterval)
            } catch {
                return
            }
            switch decide() {
            case .keepWaiting:
                continue
            case .phaseEnded:
                return
            case .requestThreadDump:
                log.launcher("The \(loaderName) installer wrote nothing for \(Self.quietPeriod.components.seconds) seconds. Asking Java for a thread dump.")
                process.requestThreadDump()
            case .threadDumpShowedNoError:
                log.launcher("The thread dump shows no installer error dialog. Waiting for the installer.")
            case .fail(let cause):
                log.launcher(describe(cause), level: .error)
                process.terminate()
                return
            }
        }
    }

    /// The failure of the phase after the process exited, or nil when the installer did not fail.
    func failure(after exit: GameProcess.Exit) -> Failure? {
        logFile?.close()
        return state.withLock { state in
            var cause = state.failureCause
            if cause == nil, state.isInstallerPhase, !exit.wasStopped, exit.code != 0 {
                cause = .exited(code: exit.code)
            }
            return cause.map { Failure(cause: $0, stackTrace: state.stackTraces.lastTrace) }
        }
    }

    private func decide() -> Decision {
        let now = clock.now
        return state.withLock { state in
            guard let phaseStart = state.phaseStart, let lastOutput = state.lastOutput else {
                return .keepWaiting
            }
            let quietTime = now - lastOutput
            if state.threadDump.isReading {
                guard quietTime >= Self.threadDumpSettleTime else {
                    return .keepWaiting
                }
                state.threadDump.finish()
                completeThreadDump(&state)
            }
            guard state.isInstallerPhase, state.failureCause == nil else {
                return .phaseEnded
            }
            if let showsError = state.completedDumpShowsError {
                state.completedDumpShowsError = nil
                guard showsError else {
                    return .threadDumpShowedNoError
                }
                state.failureCause = .errorDialog
                return .fail(.errorDialog)
            }
            if now - phaseStart >= Self.backstop {
                state.failureCause = .timedOut
                return .fail(.timedOut)
            }
            guard quietTime >= Self.quietPeriod else {
                return .keepWaiting
            }
            state.isThreadDumpRequested = true
            // The next quiet period counts from now, so a dump that never comes is asked for again.
            state.lastOutput = now
            return .requestThreadDump
        }
    }

    private func completeThreadDump(_ state: inout State) {
        logFile?.write(Self.threadDumpFooter)
        state.completedDumpShowsError = state.threadDump.showsInstallerError
    }

    private func describe(_ cause: ForgeInstallerFailureCause) -> String {
        switch cause {
        case .errorDialog:
            "The thread dump shows the \(loaderName) installer waiting at an error dialog. Stopping the game process."
        case .timedOut:
            "The \(loaderName) installer ran for more than \(Self.backstop.components.seconds / 60) minutes. Stopping the game process."
        case .exited(let code):
            "The game process exited with code \(code) before Minecraft started."
        }
    }
}

/// The first line of Minecraft's own logging, which ends the installer phase.
nonisolated enum GameLogLine {
    /// A line that starts with a `[HH:MM:SS] [` time stamp, or the ModLauncher start line.
    /// Forge 1.20.1 writes `[05:00:12] [main/INFO] …`. NeoForge 1.21.1 adds milliseconds and ANSI colors
    /// before the time stamp, for example `ESC[32m[05:00:51.992] [main/INFO] …`.
    static func matches(_ line: String) -> Bool {
        line.prefixMatch(of: #/(?:\x1B\[[0-9;]*m)*\[\d{2}:\d{2}:\d{2}(?:\.\d{3})?\] \[/#) != nil || line.contains("ModLauncher running")
    }
}
