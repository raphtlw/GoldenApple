import Foundation

/// Reads pipes with `readabilityHandler`. Unlike `FileHandle.bytes`, whose readers share one serial queue
/// and block in `read()`, several pipes can be read at once without one waiting for another.
nonisolated enum PipeReader {
    /// The data written to the pipe, in chunks, until the writing side closes it.
    static func chunks(of handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    /// All data written to the pipe.
    static func readAll(_ handle: FileHandle) async -> Data {
        var data = Data()
        for await chunk in chunks(of: handle) {
            data.append(chunk)
        }
        return data
    }

    /// Calls `onLine` for each line of UTF-8 text written to the pipe. `\n` and `\r\n` end a line.
    static func readLines(_ handle: FileHandle, onLine: (String) -> Void) async {
        var pending = Data()
        for await chunk in chunks(of: handle) {
            pending.append(chunk)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                onLine(text(pending[lineStart..<newline]))
                lineStart = pending.index(after: newline)
            }
            pending = Data(pending[lineStart...])
        }
        if !pending.isEmpty {
            onLine(text(pending))
        }
    }

    private static func text(_ line: Data) -> String {
        let withoutReturn = line.last == UInt8(ascii: "\r") ? line.dropLast() : line
        return String(decoding: withoutReturn, as: UTF8.self)
    }
}
