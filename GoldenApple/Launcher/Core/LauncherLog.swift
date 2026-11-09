import Foundation
import os

/// `os.Logger` instances for each launcher area.
nonisolated enum LauncherLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "GoldenApple"

    static let general = Logger(subsystem: subsystem, category: "General")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let metadata = Logger(subsystem: subsystem, category: "Metadata")
    static let instances = Logger(subsystem: subsystem, category: "Instances")
    static let java = Logger(subsystem: subsystem, category: "Java")
    static let launch = Logger(subsystem: subsystem, category: "Launch")
    static let content = Logger(subsystem: subsystem, category: "Content")
}
