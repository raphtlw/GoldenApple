import Foundation

nonisolated enum LaunchMode: Hashable, Sendable {
    /// Signs in with the account's Microsoft session and downloads what is missing.
    /// Offline accounts get an offline session.
    case online
    /// No network access and an offline session. `playerName` replaces the account's name when set.
    case offline(playerName: String?)
    /// The demo version. Needs no account.
    case demo(playerName: String)

    var metadataMode: MetadataMode {
        if case .offline = self {
            return .offline
        }
        return .online
    }
}

/// Where the game goes right after it starts.
nonisolated enum JoinTarget: Hashable, Sendable {
    case server(host: String, port: UInt16)
    /// The world folder name below `Minecraft/saves/`.
    case world(String)
}

nonisolated enum LaunchEvent: Sendable {
    case log(LogLine)
    case status(String)
    case gameStarted(processID: Int32)
    case gameExited(code: Int32)
}

/// One censored line from the launcher or the game.
nonisolated struct LogLine: Hashable, Sendable {
    enum Source: Sendable {
        case launcher
        case game
        /// Output of the Forge or NeoForge installer that runs inside the game process before Minecraft starts.
        case installer
        /// Thread dumps that GoldenApple asks for while it checks a quiet installer. Not meant for the normal log view.
        case diagnostic
    }

    enum Level: Sendable {
        case debug
        case info
        case warning
        case error
        case fatal
    }

    let text: String
    let level: Level
    let source: Source
    let date: Date
}

/// The log files of the last launch of an instance, in its `Logs/` folder.
nonisolated enum LaunchLogKind: CaseIterable, Sendable {
    /// `Forge Installer.log`, the installer output of the last Forge or NeoForge launch.
    case forgeInstaller
    /// `Latest Launch.log`, the whole output of the last launch, launcher lines included.
    case latestLaunch

    var fileName: String {
        switch self {
        case .forgeInstaller: "Forge Installer.log"
        case .latestLaunch: "Latest Launch.log"
        }
    }
}

/// Traits of component documents that change the command.
nonisolated enum LaunchTrait {
    static let firstThreadOnMacOS = "FirstThreadOnMacOS"
    static let quickPlaySingleplayer = "feature:is_quick_play_singleplayer"
    static let quickPlayMultiplayer = "feature:is_quick_play_multiplayer"
}
