import Foundation

/// Keeps the last Java stack trace of a stream of log lines: a line with `Exception` or `Error:`,
/// followed by its `at …`, `Caused by:`, `Suppressed:` and `... n more` lines.
nonisolated struct StackTraceCollector: Sendable {
    /// Longer traces are cut at this many lines.
    static let lineLimit = 200

    private var current: [String] = []
    private var currentHasFrames = false
    private var completed: [String] = []

    /// The last trace with at least one `at` line, or an empty list.
    var lastTrace: [String] {
        currentHasFrames ? current : completed
    }

    mutating func add(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, Self.continuesTrace(trimmed) {
            if trimmed.hasPrefix("at ") {
                currentHasFrames = true
            }
            if current.count < Self.lineLimit {
                current.append(line)
            }
            return
        }
        if currentHasFrames {
            completed = current
        }
        current = Self.startsTrace(trimmed) ? [line] : []
        currentHasFrames = false
    }

    private static func startsTrace(_ trimmed: String) -> Bool {
        trimmed.contains("Exception") || trimmed.contains("Error:")
    }

    private static func continuesTrace(_ trimmed: String) -> Bool {
        ["at ", "Caused by:", "Suppressed:", "... "].contains(where: trimmed.hasPrefix)
    }
}

/// Shortens a stack trace for an error message: every exception line with its first frames.
nonisolated enum StackTraceSummary {
    private static let framesPerException = 4

    static func summary(of trace: [String]) -> String {
        var lines: [String] = []
        var framesShown = 0
        var framesHidden = 0
        func noteHiddenFrames() {
            if framesHidden > 0 {
                lines.append("\t… \(framesHidden) more")
                framesHidden = 0
            }
        }
        for line in trace {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("at ") {
                if framesShown < framesPerException {
                    lines.append(line)
                    framesShown += 1
                } else {
                    framesHidden += 1
                }
            } else {
                noteHiddenFrames()
                lines.append(line)
                framesShown = 0
            }
        }
        noteHiddenFrames()
        return lines.joined(separator: "\n")
    }
}
