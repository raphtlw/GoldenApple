import Foundation

/// A ready-to-run game command.
nonisolated struct LaunchCommand: Sendable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]

    /// The command as shell text, for the log. Arguments with spaces or special characters are quoted.
    var displayText: String {
        ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    private static let plainCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))

    private static func shellQuoted(_ argument: String) -> String {
        let isPlain = !argument.isEmpty && argument.unicodeScalars.allSatisfy(plainCharacters.contains)
        return isPlain ? argument : "'" + argument.replacing("'", with: "'\\''") + "'"
    }
}

/// Everything a command depends on for one launch.
nonisolated struct LaunchCommandInput: Sendable {
    let instance: Instance
    let profile: LaunchProfile
    let mainClass: String
    let java: JavaInstallation
    let session: LaunchSession
    /// A server target is already resolved with SRV.
    let join: JoinTarget?
    let assetIndexName: String
    let gameAssetsFolder: URL
    let settings: LauncherSettings
    let instanceEnvironment: [String: String]
}

/// Builds the Java command line, working directory and environment of the game.
nonisolated struct LaunchCommandBuilder: Sendable {
    static let forgeWrapperMainClass = "io.github.zekerzhayard.forgewrapper.installer.Main"
    private static let removedEnvironmentVariables = ["JAVA_HOME", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "CLASSPATH"]

    let paths: LauncherPaths
    let configuration: GoldenAppleConfiguration
    let libraries: LibraryLocator

    func command(for input: LaunchCommandInput) -> LaunchCommand {
        let tokens = tokens(for: input)
        return LaunchCommand(
            executable: input.java.path,
            arguments: jvmArguments(for: input, tokens: tokens) + [input.mainClass] + gameArguments(for: input, tokens: tokens),
            workingDirectory: input.instance.gameFolder,
            environment: environment(settings: input.settings, instanceEnvironment: input.instanceEnvironment)
        )
    }

    func tokens(for input: LaunchCommandInput) -> LaunchTokens {
        let session = input.session
        return LaunchTokens([
            "auth_player_name": session.playerName,
            "auth_uuid": session.profileID,
            "auth_access_token": session.accessToken,
            "auth_session": session.sessionValue,
            "user_type": session.userType,
            "user_properties": "{}",
            "version_name": input.profile.minecraftVersion ?? input.instance.minecraftVersion,
            "version_type": input.profile.minecraftVersionType ?? "",
            "game_directory": input.instance.gameFolder.path,
            "assets_root": paths.assets.path,
            "assets_index_name": input.assetIndexName,
            "game_assets": input.gameAssetsFolder.path,
            "library_directory": paths.libraries.path,
            "profile_name": input.instance.name,
        ])
    }

    // MARK: Java options

    private func jvmArguments(for input: LaunchCommandInput, tokens: LaunchTokens) -> [String] {
        let profile = input.profile
        var arguments = CommandLineSplitter.split(input.settings.javaArguments)
        arguments += profile.jvmArguments.map(tokens.replacing(in:))
        arguments += profile.agents.compactMap(agentArgument)
        if profile.hasTrait(LaunchTrait.firstThreadOnMacOS) {
            arguments.append("-XstartOnFirstThread")
        }
        let memory = [input.settings.minimumMemoryMiB, input.settings.maximumMemoryMiB].sorted()
        arguments += [
            "-Xms\(memory[0])m",
            "-Xmx\(memory[1])m",
            "-Xdock:name=\(input.instance.name)",
            "-Dminecraft.launcher.brand=\(configuration.launcherName)",
            "-Dminecraft.launcher.version=\(configuration.launcherVersion)",
            "-Djava.library.path=\(input.instance.paths.natives.path)",
        ]
        if input.mainClass == Self.forgeWrapperMainClass {
            arguments += forgeWrapperProperties(for: profile)
        }
        arguments += ["-cp", libraries.classPath(for: profile).map(\.path).joined(separator: ":")]
        return arguments
    }

    private func agentArgument(_ agent: JavaAgent) -> String? {
        guard let jar = libraries.artifact(of: agent.library)?.localFile else {
            return nil
        }
        let option = agent.argument.nonEmpty.map { "=\($0)" } ?? ""
        return "-javaagent:\(jar.path)\(option)"
    }

    /// The properties from the ForgeWrapper README: libraries folder, Forge installer and game jar.
    private func forgeWrapperProperties(for profile: LaunchProfile) -> [String] {
        var properties = ["-Dforgewrapper.librariesDir=\(paths.libraries.path)"]
        let installer = profile.mavenFiles.first { $0.coordinate?.classifier == "installer" }
        if let installerJar = installer.flatMap(libraries.artifact(of:))?.localFile {
            properties.append("-Dforgewrapper.installer=\(installerJar.path)")
        }
        if let gameJar = profile.mainJar.flatMap(libraries.artifact(of:))?.localFile {
            properties.append("-Dforgewrapper.minecraft=\(gameJar.path)")
        }
        return properties
    }

    // MARK: Game arguments

    /// Arguments are split on spaces before tokens are replaced, so paths with spaces stay one argument.
    private func gameArguments(for input: LaunchCommandInput, tokens: LaunchTokens) -> [String] {
        let profile = input.profile
        var arguments = (profile.minecraftArguments ?? "")
            .split(separator: " ")
            .map { tokens.replacing(in: String($0)) }
        for tweaker in profile.tweakers {
            arguments += ["--tweakClass", tweaker]
        }
        arguments += ["--width", String(input.settings.windowWidth), "--height", String(input.settings.windowHeight)]
        arguments += joinArguments(input.join, profile: profile)
        if input.session.isDemo {
            arguments.append("--demo")
        }
        return arguments
    }

    private func joinArguments(_ join: JoinTarget?, profile: LaunchProfile) -> [String] {
        switch join {
        case .server(let host, let port):
            if profile.hasTrait(LaunchTrait.quickPlayMultiplayer) {
                return ["--quickPlayMultiplayer", "\(host):\(port)"]
            }
            return ["--server", host, "--port", String(port)]
        case .world(let folder):
            guard profile.hasTrait(LaunchTrait.quickPlaySingleplayer) else {
                return []
            }
            return ["--quickPlaySingleplayer", folder]
        case nil:
            return []
        }
    }

    // MARK: Environment

    /// The launcher environment without Java variables that change the JVM, plus the settings and instance variables.
    private func environment(settings: LauncherSettings, instanceEnvironment: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for name in Self.removedEnvironmentVariables {
            environment[name] = nil
        }
        environment.merge(settings.environment) { _, setting in setting }
        environment.merge(instanceEnvironment) { _, instanceValue in instanceValue }
        return environment
    }
}
