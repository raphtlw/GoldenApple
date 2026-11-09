import Foundation

nonisolated struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data

    var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }
    var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }
}

/// Runs a short-lived process and collects its output.
nonisolated enum ProcessRunner {
    /// Runs `executable` until it exits. Cancelling the task or reaching `timeout` terminates the process.
    /// Standard input is `/dev/null`.
    @concurrent
    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: Duration? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.currentDirectoryURL = currentDirectory
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        let (exitCodes, exitContinuation) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        try process.run()

        async let outputData = collect(output.fileHandleForReading)
        async let errorData = collect(errors.fileHandleForReading)
        let timer = timeout.map { timeout in
            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return false
                }
                process.terminate()
                return true
            }
        }

        let exitCode = await withTaskCancellationHandler {
            var iterator = exitCodes.makeAsyncIterator()
            return await iterator.next() ?? -1
        } onCancel: {
            process.terminate()
        }
        timer?.cancel()
        let result = ProcessResult(exitCode: exitCode, standardOutput: await outputData, standardError: await errorData)

        try Task.checkCancellation()
        if await timer?.value == true {
            throw LauncherError.processTimedOut(executable.lastPathComponent)
        }
        return result
    }

    /// Like `run`, but a non-zero exit code is an error that includes the standard error text.
    static func runChecked(
        _ executable: URL,
        arguments: [String],
        timeout: Duration? = nil
    ) async throws -> ProcessResult {
        let result = try await run(executable, arguments: arguments, timeout: timeout)
        guard result.exitCode == 0 else {
            let message = result.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LauncherError.processFailed(executable: executable.lastPathComponent, exitCode: result.exitCode, output: message)
        }
        return result
    }

    @concurrent
    private static func collect(_ handle: FileHandle) async -> Data {
        await PipeReader.readAll(handle)
    }
}
