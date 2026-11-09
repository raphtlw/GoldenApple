import Foundation
import Security

/// One failed item of a download batch.
nonisolated struct DownloadFailure: Sendable, Equatable {
    let url: URL
    let destination: URL
    let reason: String
}

/// Every error the launcher reports. Messages tell the player what went wrong and, when possible, what to do.
nonisolated enum LauncherError: LocalizedError, Sendable, Equatable {
    // Files and data
    case unsafePath(String)
    case invalidName(String)
    case unreadableFile(path: String, reason: String)
    case unsupportedFormatVersion(file: String, version: Int)

    // Network
    case networkFailure(url: URL, reason: String)
    case httpStatus(url: URL, statusCode: Int)
    case checksumMismatch(file: String, expected: String, actual: String)
    case downloadsFailed([DownloadFailure])

    // Metadata
    case metadataMissingOffline(String)
    case unknownPackage(String)
    case unknownVersion(uid: String, version: String)

    // Components
    case unsupportedMinecraftVersion(String)
    case conflictingRequirements(uid: String, firstComponent: String, firstVersion: String, secondComponent: String, secondVersion: String)
    case pinnedComponentMismatch(component: String, version: String, requiredBy: String, requiredVersion: String)
    case componentConflict(String, String)
    case componentsNeedUpdate(String)
    case resolutionDidNotFinish
    case noLoaderVersion(loader: String, minecraftVersion: String)

    // Instances
    case instanceNotFound(String)
    case missingMinecraftComponent(String)

    // Processes and archives
    case processTimedOut(String)
    case processFailed(executable: String, exitCode: Int32, output: String)
    case unsupportedArchive(String)

    // Java
    case javaPathNotSet
    case javaUnusable(String)
    case javaIncompatible(path: String, major: Int, compatible: [Int])
    case noCompatibleJava([Int])
    case javaRuntimeMissingBinary(String)

    // Accounts
    case missingMicrosoftClientID
    case signInCancelled
    case signInWindowUnavailable
    case microsoftSignInFailed(code: String, description: String)
    case deviceCodeExpired
    case xboxSignInRefused(code: Int)
    case clientIDNotApproved
    case noJavaProfile
    case unexpectedResponse(service: String, reason: String)
    case keychainFailure(status: Int32)
    case accountNotFound
    case accountNeedsSignIn(String)
    case accountRefreshUnavailable(String)
    case accountRequired
    case invalidPlayerName(String)
    case offlineAccountsNeedMicrosoftAccount

    // Launch
    case instanceAlreadyRunning(String)
    case missingMainClass(String)
    case filesMissingOffline([String])
    case gameStartFailed(String)
    case gameCrashed(exitCode: Int32)
    /// The Forge or NeoForge installer failed before Minecraft started. `stackTrace` is the last Java stack trace
    /// of the installer output, or empty. `logFile` is the path of `Forge Installer.log`.
    case forgeInstallerFailed(
        loader: String,
        loaderVersion: String,
        minecraftVersion: String,
        cause: ForgeInstallerFailureCause,
        stackTrace: [String],
        logFile: String
    )

    // Content
    case missingCurseForgeAPIKey
    case noCompatibleContentVersion(title: String, target: String)
    case contentVersionHasNoFile(title: String, version: String)
    case modpackNeedsOwnInstance(String)
    case modpackDownloadBlocked(title: String, pageURL: URL)
    case invalidModpack(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            "The path “\(path)” is not allowed because it leaves its folder."
        case .invalidName(let name):
            "“\(name)” is not a valid name. Use letters, digits or spaces."
        case .unreadableFile(let path, let reason):
            "GoldenApple could not read “\(path)”: \(reason)"
        case .unsupportedFormatVersion(let file, let version):
            "“\(file)” uses format version \(version), which this version of GoldenApple cannot read. Update GoldenApple."
        case .networkFailure(let url, let reason):
            "Could not connect to \(url.host() ?? url.absoluteString): \(reason) Check your internet connection and try again."
        case .httpStatus(let url, let statusCode):
            "The server \(url.host() ?? url.absoluteString) answered with HTTP \(statusCode) for \(url.lastPathComponent)."
        case .checksumMismatch(let file, let expected, let actual):
            "“\(file)” is damaged: its checksum is \(actual), but \(expected) was expected. Try again."
        case .downloadsFailed(let failures):
            Self.describe(failures)
        case .metadataMissingOffline(let file):
            "“\(file)” is not on this Mac yet. Connect to the internet and try again."
        case .unknownPackage(let uid):
            "The metadata server does not know the package \(uid)."
        case .unknownVersion(let uid, let version):
            "Version \(version) of \(ComponentID.displayName(uid)) does not exist."
        case .unsupportedMinecraftVersion(let version):
            "Minecraft \(version) is not supported. GoldenApple supports Minecraft 1.6.1 and newer."
        case .conflictingRequirements(let uid, let firstComponent, let firstVersion, let secondComponent, let secondVersion):
            "\(ComponentID.displayName(firstComponent)) needs \(ComponentID.displayName(uid)) \(firstVersion), but \(ComponentID.displayName(secondComponent)) needs \(ComponentID.displayName(uid)) \(secondVersion)."
        case .pinnedComponentMismatch(let component, let version, let requiredBy, let requiredVersion):
            "\(ComponentID.displayName(requiredBy)) needs \(ComponentID.displayName(component)) \(requiredVersion), but the instance uses \(ComponentID.displayName(component)) \(version). Pick versions that match."
        case .componentConflict(let first, let second):
            "\(ComponentID.displayName(first)) cannot be used together with \(ComponentID.displayName(second)). Remove one of them."
        case .componentsNeedUpdate(let reason):
            "The versions of this instance are not up to date: \(reason). Open the instance settings to fix them."
        case .resolutionDidNotFinish:
            "GoldenApple could not find a set of versions that work together for this instance."
        case .noLoaderVersion(let loader, let minecraftVersion):
            "\(loader) has no version for Minecraft \(minecraftVersion)."
        case .instanceNotFound(let name):
            "The instance “\(name)” does not exist anymore."
        case .missingMinecraftComponent(let name):
            "The instance “\(name)” has no Minecraft version. Choose one in the instance settings."
        case .processTimedOut(let executable):
            "\(executable) did not finish in time."
        case .processFailed(let executable, let exitCode, let output):
            output.isEmpty ? "\(executable) failed with exit code \(exitCode)." : "\(executable) failed with exit code \(exitCode): \(output)"
        case .unsupportedArchive(let name):
            "“\(name)” is not a zip or tar.gz archive."
        case .javaPathNotSet:
            "Automatic Java is off, but no Java path is set. Choose a Java binary in Settings or turn on automatic Java."
        case .javaUnusable(let path):
            "The Java binary at “\(path)” does not work. Choose another Java or turn on automatic Java."
        case .javaIncompatible(let path, let major, let compatible):
            "The Java at “\(path)” is Java \(major), but this version of Minecraft needs Java \(Self.list(compatible))."
        case .noCompatibleJava(let majors):
            "No compatible Java was found. This version of Minecraft needs Java \(Self.list(majors)). Install it or turn on automatic Java."
        case .javaRuntimeMissingBinary(let name):
            "The Java runtime \(name) was installed, but it has no java binary."
        case .missingMicrosoftClientID:
            "No Microsoft client ID is set, so GoldenApple cannot sign in with Microsoft. Enter the client ID of your Azure application in Settings."
        case .signInCancelled:
            "The sign-in was cancelled."
        case .signInWindowUnavailable:
            "GoldenApple needs an open window to show the Microsoft sign-in. Open the GoldenApple window and try again."
        case .microsoftSignInFailed(let code, let description):
            description.isEmpty ? "Microsoft sign-in failed (\(code))." : "Microsoft sign-in failed (\(code)): \(description)"
        case .deviceCodeExpired:
            "The sign-in code expired before it was used. Start the sign-in again."
        case .xboxSignInRefused(let code):
            Self.xboxMessage(code)
        case .clientIDNotApproved:
            "The client ID is not approved by Mojang. Minecraft services only accept Microsoft client IDs that Mojang has approved for Minecraft: Java Edition."
        case .noJavaProfile:
            "This Microsoft account has no Minecraft: Java Edition profile. Buy the game or create your profile at minecraft.net, then sign in again."
        case .unexpectedResponse(let service, let reason):
            "\(service) sent an answer GoldenApple does not understand: \(reason)"
        case .keychainFailure(let status):
            "The Keychain refused the account data: \(Self.keychainMessage(status))"
        case .accountNotFound:
            "This account is not saved in GoldenApple anymore. Choose another account."
        case .accountNeedsSignIn(let name):
            "The Microsoft sign-in for \(name) is no longer valid. Sign in again."
        case .accountRefreshUnavailable(let name):
            "GoldenApple could not reach Microsoft to refresh \(name). Check your internet connection, or play offline."
        case .accountRequired:
            "Choose an account to play with."
        case .invalidPlayerName(let name):
            "“\(name)” is not a valid player name. Use 1 to 16 letters, digits or underscores."
        case .offlineAccountsNeedMicrosoftAccount:
            "Offline accounts are available after you sign in with a Microsoft account that owns Minecraft."
        case .instanceAlreadyRunning(let name):
            "“\(name)” is already running."
        case .missingMainClass(let name):
            "The versions of “\(name)” do not name a Java main class, so the game cannot start."
        case .filesMissingOffline(let files):
            Self.describeMissing(files)
        case .gameStartFailed(let reason):
            "The game could not start: \(reason)"
        case .gameCrashed(let exitCode):
            "Game crashed with exit code \(exitCode). Look at the game log for the cause."
        case .forgeInstallerFailed(let loader, let loaderVersion, let minecraftVersion, let cause, let stackTrace, let logFile):
            Self.describeInstallerFailure(
                installer: "The \(loader) \(loaderVersion) installer for Minecraft \(minecraftVersion)",
                cause: cause,
                stackTrace: stackTrace,
                logFile: logFile
            )
        case .missingCurseForgeAPIKey:
            "CurseForge needs an API key. Set curseForgeAPIKey in Settings to your key from console.curseforge.com."
        case .noCompatibleContentVersion(let title, let target):
            "\(title) has no version for \(target)."
        case .contentVersionHasNoFile(let title, let version):
            "Version \(version) of \(title) has no file to download."
        case .modpackNeedsOwnInstance(let title):
            "\(title) is a modpack. Install it as a new instance instead of adding it to an existing one."
        case .modpackDownloadBlocked(let title, let pageURL):
            "The author of \(title) does not allow launchers to download it. Download the file from \(pageURL.absoluteString), then import it."
        case .invalidModpack(let reason):
            "This file is not a modpack GoldenApple can import: \(reason)"
        }
    }

    /// A short title for an error report.
    var title: String {
        switch self {
        case .unsafePath: "Unsafe file path"
        case .invalidName: "Invalid name"
        case .unreadableFile, .unsupportedFormatVersion: "Unreadable file"
        case .networkFailure: "No connection"
        case .httpStatus: "Server error"
        case .checksumMismatch: "Damaged download"
        case .downloadsFailed: "Downloads failed"
        case .metadataMissingOffline: "Not available offline"
        case .unknownPackage, .unknownVersion: "Unknown version"
        case .unsupportedMinecraftVersion: "Unsupported Minecraft version"
        case .conflictingRequirements, .pinnedComponentMismatch, .componentConflict, .componentsNeedUpdate, .resolutionDidNotFinish:
            "Versions do not match"
        case .noLoaderVersion: "No mod loader version"
        case .instanceNotFound: "Instance not found"
        case .missingMinecraftComponent: "No Minecraft version"
        case .processTimedOut, .processFailed: "Tool failed"
        case .unsupportedArchive: "Unsupported archive"
        case .javaPathNotSet, .javaUnusable, .javaIncompatible, .noCompatibleJava, .javaRuntimeMissingBinary: "Java problem"
        case .missingMicrosoftClientID, .signInCancelled, .signInWindowUnavailable, .microsoftSignInFailed, .deviceCodeExpired,
             .xboxSignInRefused, .clientIDNotApproved, .noJavaProfile, .accountNeedsSignIn, .accountRefreshUnavailable:
            "Sign-in failed"
        case .unexpectedResponse: "Unexpected server answer"
        case .keychainFailure: "Keychain error"
        case .accountNotFound, .accountRequired, .invalidPlayerName, .offlineAccountsNeedMicrosoftAccount: "Account problem"
        case .instanceAlreadyRunning: "Already running"
        case .missingMainClass, .gameStartFailed: "Game did not start"
        case .filesMissingOffline: "Game files missing"
        case .gameCrashed: "Game crashed"
        case .forgeInstallerFailed(let loader, _, _, _, _, _): "\(loader) installer failed"
        case .missingCurseForgeAPIKey: "CurseForge API key missing"
        case .noCompatibleContentVersion, .contentVersionHasNoFile: "No compatible file"
        case .modpackNeedsOwnInstance, .invalidModpack: "Modpack problem"
        case .modpackDownloadBlocked: "Download blocked"
        }
    }

    private static func describeInstallerFailure(installer: String, cause: ForgeInstallerFailureCause, stackTrace: [String], logFile: String) -> String {
        let summary = stackTrace.isEmpty ? nil : StackTraceSummary.summary(of: stackTrace)
        var parts: [String]
        switch cause {
        case .errorDialog:
            parts = summary.map { ["\(installer) failed:", $0] } ?? ["\(installer) stopped at an error dialog that macOS cannot show."]
        case .timedOut:
            let minutes = ForgeInstallerMonitor.backstop.components.seconds / 60
            parts = ["\(installer) did not finish within \(minutes) minutes, so GoldenApple stopped it."]
        case .exited(let code):
            parts = ["\(installer) failed, and the game process exited with code \(code)."]
        }
        if cause != .errorDialog, let summary {
            parts.append("The last error in its output:\n\(summary)")
        }
        parts.append("The installer log is in “\(logFile)”.")
        return parts.joined(separator: "\n\n")
    }

    private static func describe(_ failures: [DownloadFailure]) -> String {
        let shown = failures.prefix(5).map { "\($0.destination.lastPathComponent): \($0.reason)" }
        let more = failures.count > shown.count ? "\n…and \(failures.count - shown.count) more." : ""
        return "\(failures.count) download(s) failed:\n" + shown.joined(separator: "\n") + more
    }

    private static func describeMissing(_ files: [String]) -> String {
        let shown = files.prefix(5).joined(separator: "\n")
        let more = files.count > 5 ? "\n…and \(files.count - 5) more." : ""
        return "\(files.count) game file(s) are not on this Mac yet. Connect to the internet and launch once online:\n" + shown + more
    }

    private static func xboxMessage(_ code: Int) -> String {
        switch code {
        case 2148916233:
            "This Microsoft account has no Xbox account. Create one at xbox.com, then sign in again."
        case 2148916235:
            "Xbox Live is not available in the country of this account."
        case 2148916236, 2148916237:
            "This account needs age verification. Complete it at xbox.com, then sign in again."
        case 2148916238:
            "This is a child account. An adult must add it to a Microsoft family at account.microsoft.com before it can sign in."
        default:
            "Xbox Live refused the sign-in (error \(code))."
        }
    }

    private static func keychainMessage(_ status: Int32) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String?
        return message.map { "\($0) (\(status))" } ?? "error \(status)"
    }

    private static func list(_ majors: [Int]) -> String {
        majors.isEmpty ? "(unknown)" : majors.map(String.init).joined(separator: " or ")
    }
}
