import Foundation
import os
import Synchronization

/// The running game. Reports each output line and waits until the process exits.
nonisolated final class GameProcess: Sendable {
    struct Exit: Sendable {
        let code: Int32
        /// The exit followed `stop()`.
        let wasStopped: Bool
    }

    /// After `stop()`, a game that is still running after this delay is killed.
    private static let forcedStopDelay = Duration.seconds(10)

    private let process = Process()
    private let isStopRequested = Mutex(false)

    init(_ command: LaunchCommand) {
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = FileHandle.nullDevice
    }

    /// Starts the game, calls `onStart` with its process ID, and sends every line of standard output and standard error to `onLine`.
    func run(onStart: (Int32) -> Void, onLine: @escaping @Sendable (_ line: String, _ isStandardError: Bool) -> Void) async throws -> Exit {
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let (exitCodes, exitContinuation) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw LauncherError.gameStartFailed(error.localizedDescription)
        }
        if isStopRequested.withLock({ $0 }) {
            process.terminate()
        }
        onStart(process.processIdentifier)

        async let outputFinished: Void = Self.readLines(output.fileHandleForReading, isStandardError: false, onLine: onLine)
        async let errorsFinished: Void = Self.readLines(errors.fileHandleForReading, isStandardError: true, onLine: onLine)
        var iterator = exitCodes.makeAsyncIterator()
        let code = await iterator.next() ?? -1
        _ = await (outputFinished, errorsFinished)
        return Exit(code: code, wasStopped: isStopRequested.withLock { $0 })
    }

    /// Stops the game on the player's request. The exit then counts as stopped, not as a crash.
    func stop() {
        isStopRequested.withLock { $0 = true }
        terminate()
    }

    /// Asks the game to quit with SIGTERM, and kills it when it is still running after a delay.
    func terminate() {
        guard process.isRunning else {
            return
        }
        process.terminate()
        let process = process
        let processID = process.processIdentifier
        Task {
            try? await Task.sleep(for: Self.forcedStopDelay)
            if process.isRunning {
                LauncherLog.launch.info("Killing game process \(processID) because it did not stop")
                kill(processID, SIGKILL)
            }
        }
    }

    /// Sends SIGQUIT. A HotSpot JVM then prints a thread dump to standard output and keeps running.
    func requestThreadDump() {
        guard process.isRunning else {
            return
        }
        kill(process.processIdentifier, SIGQUIT)
    }

    @concurrent
    private static func readLines(_ handle: FileHandle, isStandardError: Bool, onLine: @Sendable (String, Bool) -> Void) async {
        await PipeReader.readLines(handle) { line in
            onLine(line, isStandardError)
        }
    }
}

/// One launch, from preparation until the game exits.
nonisolated final class RunningGame: Sendable {
    private struct State {
        var task: Task<Int32, any Error>?
        var process: GameProcess?
        var isStopRequested = false
    }

    let instanceID: String
    private let state = Mutex(State())

    init(instanceID: String) {
        self.instanceID = instanceID
    }

    /// The task that prepares and runs the game. A stop that came first cancels it at once.
    func attach(_ task: Task<Int32, any Error>) {
        let isStopRequested = state.withLock { state in
            state.task = task
            return state.isStopRequested
        }
        if isStopRequested {
            task.cancel()
        }
    }

    func attach(_ process: GameProcess) {
        let isStopRequested = state.withLock { state in
            state.process = process
            return state.isStopRequested
        }
        if isStopRequested {
            process.stop()
        }
    }

    /// Before the game starts, this cancels the preparation. After it starts, it stops the game process.
    func stop() {
        let (task, process) = state.withLock { state in
            state.isStopRequested = true
            return (state.task, state.process)
        }
        if let process {
            process.stop()
        } else {
            task?.cancel()
        }
    }

    func waitUntilFinished() async {
        _ = await state.withLock { $0.task }?.result
    }
}

/// The launches in progress, one per instance.
nonisolated final class RunningGames: Sendable {
    private let games = Mutex<[String: RunningGame]>([:])

    func begin(_ instance: Instance) throws -> RunningGame {
        try games.withLock { games in
            guard games[instance.id] == nil else {
                throw LauncherError.instanceAlreadyRunning(instance.name)
            }
            let game = RunningGame(instanceID: instance.id)
            games[instance.id] = game
            return game
        }
    }

    func end(_ game: RunningGame) {
        games.withLock { games in
            if games[game.instanceID] === game {
                games[game.instanceID] = nil
            }
        }
    }

    func game(for instanceID: String) -> RunningGame? {
        games.withLock { $0[instanceID] }
    }
}
