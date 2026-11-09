import Foundation
import os
import Synchronization

/// A log file in the instance `Logs/` folder that receives censored lines while a launch runs.
/// Opening it replaces the file of the previous launch.
nonisolated final class LaunchLogFile: Sendable {
    let url: URL
    private let handle: Mutex<FileHandle?>

    init(replacing url: URL) throws {
        try FileSystem.createFolder(url.deletingLastPathComponent())
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw LauncherError.unreadableFile(path: url.path, reason: "The file could not be created.")
        }
        self.url = url
        handle = Mutex(try FileHandle(forWritingTo: url))
    }

    deinit {
        close()
    }

    /// Writes one line. After a write error the file stays as it is and later lines are dropped.
    func write(_ line: String) {
        handle.withLock { handle in
            guard let file = handle else {
                return
            }
            do {
                try file.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                LauncherLog.launch.error("Stopped writing \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? file.close()
                handle = nil
            }
        }
    }

    func close() {
        handle.withLock { handle in
            try? handle?.close()
            handle = nil
        }
    }

    /// The lines of a log file without the thread dumps, at most `limit` from the end. Nil when the file does not exist.
    static func tail(of url: URL, limit: Int) -> [String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var lines: [String] = []
        var isInThreadDump = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            switch line {
            case ForgeInstallerMonitor.threadDumpHeader: isInThreadDump = true
            case ForgeInstallerMonitor.threadDumpFooter: isInThreadDump = false
            default:
                if !isInThreadDump {
                    lines.append(line)
                }
            }
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return Array(lines.suffix(limit))
    }
}
