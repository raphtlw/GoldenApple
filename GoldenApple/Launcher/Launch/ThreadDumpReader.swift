import Foundation

/// Finds the lines of a HotSpot thread dump in standard output, after GoldenApple sent `SIGQUIT`.
///
/// A dump starts with a time stamp line (`2026-11-09 12:52:25`) or `Full thread dump`, lists the threads,
/// and ends with `JNI global refs: …`. A heap summary can follow after an empty line, from a `Heap` line
/// to the next empty line.
nonisolated struct ThreadDumpReader: Sendable {
    private enum Position {
        case outside
        case threads
        /// After `JNI global refs`. The dump is over at the first line that is neither empty nor `Heap`.
        case afterReferences
        case heap
    }

    /// Frames that show the installer stuck at its error dialog.
    private static let installerErrorFrames = ["javax.swing.JOptionPane.", "net.minecraftforge.installer.actions.PostProcessors.error("]

    private var position = Position.outside
    private(set) var showsInstallerError = false

    var isReading: Bool {
        position != .outside
    }

    /// True when the line belongs to a dump. `isExpectingDump` is true after GoldenApple asked for a dump
    /// that has not started yet, so a time stamp line from other output does not start one.
    mutating func read(_ line: String, isExpectingDump: Bool) -> Bool {
        switch position {
        case .outside:
            guard line.hasPrefix("Full thread dump") || (isExpectingDump && Self.isTimeStamp(line)) else {
                return false
            }
            position = .threads
            showsInstallerError = false
        case .threads:
            if line.hasPrefix("JNI global refs:") {
                position = .afterReferences
            }
        case .afterReferences:
            if line == "Heap" {
                position = .heap
            } else if !line.isEmpty {
                position = .outside
                return false
            }
        case .heap:
            if line.isEmpty {
                position = .outside
            }
        }
        if Self.installerErrorFrames.contains(where: line.contains) {
            showsInstallerError = true
        }
        return true
    }

    /// Ends the dump, for example when output stopped before its last line.
    mutating func finish() {
        position = .outside
    }

    /// `yyyy-MM-dd HH:mm:ss`, the first line HotSpot prints for a dump.
    private static func isTimeStamp(_ line: String) -> Bool {
        line.wholeMatch(of: #/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/#) != nil
    }
}
