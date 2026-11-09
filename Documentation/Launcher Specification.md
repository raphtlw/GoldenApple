# GoldenApple Launcher Specification

This document describes what the GoldenApple launcher library does. It is the only design input for the code in `GoldenApple/Launcher/`. It was written from public sources: the JSON that public servers return, Mojang's published file formats, Microsoft, Xbox and Minecraft services documentation, the Modrinth and CurseForge API documentation, the Modrinth pack format, and the ForgeWrapper README.

## Rules for implementers

- Write the code from this document, public documentation and responses from the public endpoints named here.
- Do not open, search or read `/Users/raphael/Desktop/PrismLauncher`, `/Users/raphael/Desktop/GoldenApple Prism Port Archive`, or the PrismLauncher, MultiMC or PolyMC source code on GitHub or anywhere else. Do not use their class names or comments.
- You may fetch the public endpoints in this document (with `curl`) to see real responses.
- macOS 27 on Apple Silicon only. No Linux, Windows or Intel code paths. Java on the user's Mac is arm64.
- Swift, Foundation, CryptoKit, Synchronization, os, AuthenticationServices, Security and dnssd only. No third-party packages.

## Build environment

The Xcode project uses `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` (this turns on `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`) and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`. The App Sandbox is off. Files in `GoldenApple/` are compiled automatically (synchronized folder), so a new `.swift` file needs no project change.

Because of the MainActor default, every launcher type must be marked `nonisolated` (structs, enums, classes, protocols) or be an `actor`. Heavy work (hashing, file walks, process waits) goes in `@concurrent` functions or actors so it never runs on the main thread. Use `Synchronization.Mutex` for shared mutable state in classes. Import every module whose members you use (`import os` for `Logger`, `import Synchronization` for `Mutex`).

Build with `mise run build` from `/Users/raphael/Desktop/GoldenApple`. The result must have zero errors and zero warnings. To test without the app, compile a command-line harness in `/private/tmp/claude-501/<Your Folder>/` with:

```
xcrun swiftc -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature MemberImportVisibility \
  -parse-as-library -o harness main.swift $(fd -e swift . /Users/raphael/Desktop/GoldenApple/GoldenApple/Launcher)
```

Give the harness a data root inside `/private/tmp/claude-501/` and delete everything you created there when you finish. Never write to `~/Library/Application Support/GoldenApple`. Do not commit or push.

## Data layout

All launcher files live below one root, `~/Library/Application Support/GoldenApple/` by default. The root can be replaced for tests.

```
GoldenApple/
├── Instances/<Instance Name>/
│   ├── Instance.json            instance settings and Java check cache
│   ├── Components.json          Minecraft, LWJGL and loader versions
│   ├── Installed Content.json   files installed from Modrinth or CurseForge
│   ├── Logs/                    Latest Launch.log, Forge Installer.log
│   ├── Natives/                 native libraries, only while the game runs
│   └── Minecraft/               game directory: mods, saves, config, logs, resourcepacks, shaderpacks
├── Versions/
│   ├── index.json               package index from the metadata server
│   └── <uid>/
│       ├── index.json           version list of the package
│       └── <version>/
│           ├── version.json     component version document
│           └── client.jar       game jar, only for uid net.minecraft
├── Libraries/                   Maven layout: group/with/slashes/artifact/version/artifact-version[-classifier].ext
├── Assets/
│   ├── indexes/<id>.json        lowercase names, the game expects them
│   ├── objects/<xx>/<hash>
│   └── virtual/<id>/...
├── Java/<runtime name>/         downloaded Java runtimes
├── Cache/
│   ├── Downloads/               partial downloads, emptied at startup
│   ├── Java Archives/
│   └── HTTP Cache.json          ETag and Last-Modified per cached URL
├── Accounts.json                account list without secrets
└── Settings.json                launcher settings
```

Account tokens are stored in the macOS Keychain, not in files (see Accounts).

Instance folder names come from the instance name with `/`, `:` and other unsafe characters removed. If the folder exists, append ` 2`, ` 3` and so on. Version folder names use the version string with `/` replaced by `-`.

Write every JSON file atomically, pretty-printed with sorted keys. Use `Codable` models for all of GoldenApple's own files. Each own file has `"formatVersion": 1`.

## Configuration and settings

`GoldenAppleConfiguration` (a `Sendable` struct with a `static let default`) holds build-time values:

| Field | Default |
| --- | --- |
| `launcherName` | `GoldenApple` |
| `launcherVersion` | `CFBundleShortVersionString`, or `1.0` |
| `userAgent` | `GoldenApple/<version>` |
| `metadataBaseURL` | `https://meta.prismlauncher.org/v1/` |
| `libraryBaseURL` | `https://libraries.minecraft.net/` |
| `resourceBaseURL` | `https://resources.download.minecraft.net/` |
| `microsoftClientID` | empty |
| `microsoftRedirectURI` | `goldenapple://oauth/microsoft` |
| `curseForgeAPIKey` | empty |
| `dataDirectoryName` | `GoldenApple` |

`LauncherSettings` (Codable, stored in `Settings.json`) holds user settings. Missing keys decode to the defaults, so old files keep working.

| Field | Type | Default |
| --- | --- | --- |
| `minimumMemoryMiB` | Int | 512 |
| `maximumMemoryMiB` | Int | total RAM / 1.5 when RAM is below 6 GiB, else 4096 |
| `windowWidth`, `windowHeight` | Int | 854, 480 |
| `javaArguments` | String | empty (split like a shell command line, with single and double quotes) |
| `environment` | [String: String] | empty |
| `automaticJava` | Bool | true (pick or download the right Java per instance) |
| `javaPath` | String? | nil (used when `automaticJava` is false) |
| `concurrentDownloads` | Int | 6 |
| `metadataURLOverride` | String? | nil |
| `microsoftClientIDOverride` | String? | nil |
| `curseForgeAPIKey` | String? | nil |
| `onboardingCompleted` | Bool | false |

The effective client ID and CurseForge key are the setting when it is set and non-empty, else the configuration value.

## Metadata server

GoldenApple reads component metadata from `metadataBaseURL` (or `metadataURLOverride`). Three document kinds exist:

- `index.json`: `{ "formatVersion": 1, "packages": [ { "uid", "name", "sha256" } ] }`. `sha256` is the hash of `<uid>/index.json`.
- `<uid>/index.json`: `{ "formatVersion": 1, "uid", "name", "versions": [ { "version", "type", "releaseTime", "recommended", "volatile", "requires", "conflicts", "sha256" } ] }`. `sha256` is the hash of `<uid>/<version>.json`. `type` is `release`, `snapshot`, `old_beta`, `old_alpha` or other strings.
- `<uid>/<version>.json`: a component version document (below).

Packages GoldenApple uses: `net.minecraft`, `org.lwjgl`, `org.lwjgl3`, `net.fabricmc.fabric-loader`, `net.fabricmc.intermediary`, `org.quiltmc.quilt-loader`, `org.quiltmc.hashed`, `net.minecraftforge`, `net.neoforged`, `net.minecraft.java`, `com.azul.java`, `net.adoptium.java`.

Loading rules:

- `index.json` is fetched once per launcher run with an ETag or Last-Modified conditional request. A 304 reuses the local file.
- A version list or version document on disk is used when its sha256 matches the value from the parent listing. Otherwise download it, verify the sha256, then store it. A mismatch after download is an error.
- In offline mode, use the files on disk without network access, and fail when a file is missing.
- Accept `formatVersion` 0 or 1 and reject others.

### Component version document

Fields seen in the public documents. Fields not listed (for example `logging`) are ignored.

| Field | Meaning |
| --- | --- |
| `uid`, `version`, `name`, `type`, `releaseTime` | identity |
| `order` | Int. Components apply in ascending `order`, ties keep list order. Minecraft is -2, LWJGL -1, loaders 5 to 11. |
| `requires` | `[ { "uid", "equals"?, "suggests"? } ]`. `equals` is a hard version requirement, `suggests` a preferred version. |
| `conflicts` | same shape, packages that must not be present |
| `volatile` | true for components that exist only as a dependency (LWJGL, intermediary). They are removed when nothing requires them. |
| `mainClass` | Java main class. The last component with a non-empty value wins. |
| `minecraftArguments` | game arguments, separated by single spaces, with `${token}` placeholders. The last non-empty value wins. |
| `+jvmArgs` | extra JVM arguments with tokens, added in component order |
| `+traits` | strings, unioned. Used: `FirstThreadOnMacOS`, `feature:is_quick_play_singleplayer`, `feature:is_quick_play_multiplayer`, `legacyLaunch`, `alphaLaunch`. |
| `+tweakers` | strings. Each becomes `--tweakClass <name>`. A repeated tweaker moves to the end. |
| `mainJar` | a library object for the game jar (`com.mojang:minecraft:<version>:client`) |
| `libraries` | library objects for the class path and natives |
| `mavenFiles` | library objects that are downloaded but not put on the class path (Forge and NeoForge installers) |
| `+agents` | library objects with an optional `argument`. Each becomes `-javaagent:<jar>[=argument]`. |
| `assetIndex` | `{ "id", "sha1", "size", "totalSize", "url" }` |
| `compatibleJavaMajors` | Ints, for example `[21]` |
| `compatibleJavaName` | Mojang runtime component name, for example `java-runtime-delta` or `jre-legacy` |
| `runtimes` | only in `net.minecraft.java`, `com.azul.java` and `net.adoptium.java` documents (see Java) |

### Library object

```
{
  "name": "group:artifact:version[:classifier][@extension]",
  "url": "https://maven.example/"             optional Maven repository base, null means none
  "downloads": {
    "artifact": { "url", "sha1", "size", "path"? },
    "classifiers": { "<classifier>": { "url", "sha1", "size" } }
  },
  "natives": { "<os key>": "<classifier>" },   classifier may contain ${arch}
  "extract": { "exclude": [ "META-INF/" ] },
  "rules": [ { "action": "allow" | "disallow", "os": { "name": "<os key>" }? } ]
}
```

Storage path: Maven layout below `Libraries/`. `group` dots become slashes. File name is `artifact-version[-classifier].extension`, extension `jar` by default. The game jar (`com.mojang:minecraft:<v>:client`) is the exception and is stored at `Versions/net.minecraft/<v>/client.jar`.

Download URL: `downloads.artifact.url` when present (or the classifier entry for natives). Otherwise `url` + Maven path, or `libraryBaseURL` + Maven path when `url` is absent or null. Verify `sha1` when given.

### Platform matching

GoldenApple runs arm64 Java, so its OS key is `osx-arm64`. Library sets publish separate entries for `osx` (Intel) and `osx-arm64`, so `osx` must not match on Apple Silicon.

- A library without `rules` is active.
- A library with `rules` starts as disallowed. Walk the rules in order. A rule without `os` always applies. A rule with `os.name` applies when the name equals the OS key. The last rule that applies decides.
- For `natives`, use the entry for `osx-arm64`. Replace `${arch}` with `64`. A natives library without an `osx-arm64` entry is inactive.

### Merging components into a launch profile

Apply enabled components in ascending `order`. For libraries, a later library with the same group, artifact and classifier replaces an earlier one only when its version compares higher. Version comparison splits the string into runs of digits and non-digits and compares digit runs numerically and text runs as strings, so `1.10` is above `1.9` and `3.3.3` above `3.3.1`. Natives libraries are kept in a separate list.

### Supported Minecraft versions

GoldenApple supports Minecraft 1.6.1 and newer. Version lists shown to users only contain versions whose `releaseTime` is at or after the `releaseTime` of `1.6.1` in the same list. Creating an instance or changing its Minecraft version loads the version document and refuses it when `mainClass` is empty or the traits contain `legacyLaunch` or `alphaLaunch`.

## Components and dependency resolution

`Components.json`:

```
{
  "formatVersion": 1,
  "components": [
    { "uid": "net.minecraft", "version": "1.21.4", "isDependency": false, "isPinned": true, "isEnabled": true }
  ]
}
```

`isPinned` marks the component the user picked (Minecraft is always pinned). `isDependency` marks components added automatically.

Resolution runs after every change and before every launch:

1. Load the version document of every component (from disk or the server).
2. Collect all `requires` of enabled components. Two requirements on the same uid combine. Both `equals` values must match or the resolution fails. For `suggests`, keep the higher one.
3. Remove dependency components that are volatile and no longer required. Repeat until stable.
4. For each requirement whose uid is missing, add a dependency component. Its version is `equals`, else `suggests`, else for `net.fabricmc.intermediary` and `org.quiltmc.hashed` the Minecraft version, else the newest `release` version of that package.
5. For each requirement whose `equals` differs from a dependency component's version, change that version. If it differs from a pinned component, fail with a message that names both components.
6. Repeat from step 1 until nothing changes.
7. When the Minecraft version changes, set every loader component to the recommended (else newest) loader version for the new Minecraft version, and let steps 3 to 5 fix LWJGL and intermediary.
8. A conflict between two present components is an error. Fabric, Quilt, Forge and NeoForge conflict with each other.

Before a launch the same resolution runs in check mode. Any change it would make is an error instead.

Mod loader choices: Fabric (`net.fabricmc.fabric-loader`), Quilt (`org.quiltmc.quilt-loader`), Forge (`net.minecraftforge`), NeoForge (`net.neoforged`). For the user list of loader versions, Forge and NeoForge versions are filtered to those whose `requires` has `net.minecraft` with `equals` the instance Minecraft version. Fabric and Quilt versions are independent of Minecraft. A recommended loader version has `"recommended": true`. Use the first recommended version, else the newest.

## Downloads

- One `URLSession` with the user agent, no URL cache, and a request timeout of at least 15 seconds.
- Retry network errors twice with a short delay. HTTP errors are not retried.
- Downloads go into `Cache/Downloads/<uuid>.part`. Verify the hash (SHA-1, SHA-256 or SHA-512 by CryptoKit, streaming in 1 MiB chunks), then move the file into place. A mismatch deletes the part file and fails that item.
- Skip a file that exists and matches its expected hash. Asset objects are skipped when the size matches.
- Run up to `concurrentDownloads` downloads at once with a task group. Try all items, then report all failures together.
- Report progress with Foundation's `ProgressManager` (macOS 27). A function that downloads takes `subprogress: consuming Subprogress? = nil` and calls `start(totalCount:)` on it. Set `totalFileCount`, `completedFileCount`, `totalByteCount` and `completedByteCount` on the manager as files finish.

## Assets

1. Download the asset index from `assetIndex.url` to `Assets/indexes/<id>.json` and verify `sha1`.
2. The index is `{ "objects": { "<path>": { "hash", "size" } }, "virtual"?: Bool, "map_to_resources"?: Bool }`.
3. Download each object from `resourceBaseURL + <hash[0..2]>/<hash>` to `Assets/objects/<hash[0..2]>/<hash>`.
4. When `virtual` is true, copy objects to `Assets/virtual/<id>/<path>`. When `map_to_resources` is true, copy them to `<game directory>/resources/<path>`. Copy only missing files.

`${assets_root}` is the `Assets` folder. `${game_assets}` is `Assets/virtual/<id>` for virtual indexes, `<game directory>/resources` for `map_to_resources`, else `Assets/virtual/<id>`.

## Java

### Checking a Java binary

Run `<java> -XshowSettings:properties -version` with a 15 second timeout. Parse `    key = value` lines from standard error. Read `java.version`, `java.vendor` and `os.arch`. A binary that fails, times out or lacks those keys is unusable. Cache the result in `Instance.json` with a signature made from the binary path and its modification time, and check again when the signature changes.

Java versions parse as `1.<major>.<minor>_<security>` for old versions and `<major>.<minor>.<security>` for new ones.

### Discovering installed Java

Candidates: `Java/*/bin/java` and `Java/*/Contents/Home/bin/java` in the data root, `/Library/Java/JavaVirtualMachines/*/Contents/Home/bin/java`, `~/Library/Java/JavaVirtualMachines/*/Contents/Home/bin/java`, and `/usr/libexec/java_home -V` output. Check each with the Java check. Keep only `aarch64` binaries.

### Choosing Java for a launch

When `automaticJava` is on:

1. If `Java/<compatibleJavaName>/bin/java` exists and passes the check, use it.
2. Else load `net.minecraft.java` version `java<major>` for each major in `compatibleJavaMajors`. Find a runtime with `runtimeOS` equal to `mac-os-arm64` and `name` equal to `compatibleJavaName`. If there is none, take any runtime with `runtimeOS` `mac-os-arm64` in that document. Install it to `Java/<compatibleJavaName>/`.
3. If nothing is found, look for an installed Java (discovery) whose major is compatible.
4. Fail with a clear message when no compatible Java exists.

When `automaticJava` is off, use `javaPath`. A major outside `compatibleJavaMajors` is an error.

### Runtime entries

```
{ "name", "vendor", "runtimeOS", "downloadType": "manifest" | "archive", "packageType", "url",
  "checksum": { "type": "sha1" | "sha256", "hash" }, "version": { "major", "minor", "security", "build", "name" } }
```

- `manifest`: `url` is a Mojang file manifest. Verify the manifest with `checksum`. It has `{ "files": { "<relative path>": { "type": "file" | "directory" | "link", "executable"?, "target"?, "downloads": { "raw": { "url", "sha1", "size" } } } } }`. Create directories, download files with SHA-1 checks, set the executable bit when `executable` is true, then create symbolic links.
- `archive`: `url` is a zip or tar.gz. Download it to `Cache/Java Archives/`, verify `checksum`, and extract it with `/usr/bin/ditto -x -k` (zip) or `/usr/bin/tar -xzf` (tar). When the archive has one top-level folder, put its contents directly into the runtime folder.
- macOS runtimes keep the binary at `<bundle>.bundle/Contents/Home/bin/java` or `<folder>/Contents/Home/bin/java`. After installing, when `<runtime>/bin/java` does not exist, create symbolic links in the runtime folder that point to each entry of that `Contents/Home` folder.

## Accounts

`Accounts.json` stores the account list without secrets: `{ "formatVersion": 1, "defaultAccountID", "accounts": [ { "id", "kind": "microsoft" | "offline", "profileID", "profileName", "skinURL"?, "ownsMinecraft", "clientID"?, "lastRefreshed"? } ] }`.

Secrets (Microsoft refresh token and the Minecraft access token with its expiry) are stored in the Keychain as one generic password item per account: service `GoldenApple Accounts`, account = the account ID, data = JSON.

### Microsoft sign-in

Scope `XboxLive.SignIn XboxLive.offline_access`. Endpoints on `https://login.microsoftonline.com/consumers/oauth2/v2.0/`:

- Browser flow: `authorize` with `client_id`, `response_type=code`, `redirect_uri`, `scope`, `state`, `code_challenge` (S256 PKCE), `code_challenge_method=S256`, `prompt=select_account`. Present it with `ASWebAuthenticationSession` using `.customScheme("goldenapple")`. Check `state`, then POST form-encoded to `token` with `grant_type=authorization_code`, `code`, `redirect_uri`, `code_verifier`, `client_id`, `scope`.
- Device code flow: POST `devicecode` with `client_id` and `scope`. Show `user_code` and `verification_uri` through an event. Poll `token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code`, `client_id`, `device_code` every `interval` seconds. `authorization_pending` means keep polling. `slow_down` adds 5 seconds. Stop at `expires_in`.
- Refresh: POST `token` with `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope`. Keep the old refresh token when the response has none.

### Xbox and Minecraft services

1. POST `https://user.auth.xboxlive.com/user/authenticate` with `{ "Properties": { "AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=<microsoft access token>" }, "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT" }` and header `x-xbl-contract-version: 1`. Read `Token` and `DisplayClaims.xui[0].uhs`.
2. POST `https://xsts.auth.xboxlive.com/xsts/authorize` with `{ "Properties": { "SandboxId": "RETAIL", "UserTokens": [ "<user token>" ] }, "RelyingParty": "rp://api.minecraftservices.com/", "TokenType": "JWT" }`. A 401 carries `XErr`. Map 2148916233 (no Xbox account), 2148916235 (country blocked), 2148916236 and 2148916237 (age verification), 2148916238 (child account needs a family) to clear messages.
3. POST `https://api.minecraftservices.com/launcher/login` with `{ "xtoken": "XBL3.0 x=<uhs>;<xsts token>", "platform": "PC_LAUNCHER" }`. Read `access_token` and `expires_in`. HTTP 403 here means the client ID is not approved by Mojang. Say exactly that.
4. GET `https://api.minecraftservices.com/entitlements/license?requestId=<uuid>` with `Authorization: Bearer <access token>`. Items named `product_minecraft` or `game_minecraft` mean the account owns the game.
5. GET `https://api.minecraftservices.com/minecraft/profile` with the bearer token. 404 means no Java profile. Read `id`, `name` and the active skin URL.

Refresh before a launch when the Minecraft token expires within 12 hours. A failed refresh because of a network error lets the user play offline. An invalid refresh token marks the account as needing sign-in again.

### Offline accounts

An offline account has a name of 1 to 16 letters, digits or underscores. Its profile ID is a version 3 UUID: MD5 of `OfflinePlayer:<name>`, then byte 6 = `(byte & 0x0f) | 0x30` and byte 8 = `(byte & 0x3f) | 0x80`, written as 32 lowercase hex digits. In Release builds, offline accounts can be added only when a Microsoft account that owns Minecraft is saved. In Debug builds (`#if DEBUG`), offline accounts can be added and launched without any Microsoft account, so the app can be developed and tested before the Microsoft client ID is approved. The Debug exception must not exist in Release builds. A demo launch needs no account in any build.

## Launching

Order of work:

1. Resolve components in check mode (online, or offline when asked).
2. Choose and check Java.
3. Online: download libraries, natives, `mavenFiles`, agents and the game jar, then the asset index and objects. Offline: fail when any of these files is missing.
4. Extract natives into the instance `Natives/` folder. Skip entries under `extract.exclude` prefixes. Rename `.jnilib` files to `.dylib`.
5. Copy virtual or resource assets when the index asks for it.
6. Build the command and start the process.
7. Delete `Natives/` after the process exits.

### Tokens

| Token | Value |
| --- | --- |
| `auth_player_name` | player name |
| `auth_uuid` | profile ID without dashes |
| `auth_access_token` | Minecraft access token, `0` offline |
| `auth_session` | `token:<access token>:<profile id>`, `-` offline |
| `user_type` | `msa`, or `legacy` for offline and demo sessions |
| `user_properties` | `{}` |
| `version_name` | Minecraft version |
| `version_type` | Minecraft version `type` |
| `game_directory` | instance `Minecraft/` path |
| `assets_root`, `assets_index_name`, `game_assets` | see Assets |
| `library_directory` | `Libraries/` path |
| `profile_name` | instance name |

Unknown tokens become empty text.

### Command

```
<java>
  <settings.javaArguments split like a shell>
  <each +jvmArgs entry with tokens replaced>
  -javaagent:<jar>[=argument] for each agent
  -XstartOnFirstThread                        when trait FirstThreadOnMacOS is present
  -Xms<min>m -Xmx<max>m                       the smaller value is -Xms
  -Xdock:name=<instance name>
  -Dminecraft.launcher.brand=GoldenApple -Dminecraft.launcher.version=<version>
  -Djava.library.path=<instance Natives/>
  ForgeWrapper properties (below) when mainClass is io.github.zekerzhayard.forgewrapper.installer.Main
  -cp <library jars in profile order>:<client.jar>
  <mainClass>
  <minecraftArguments split on spaces, tokens replaced>
  --tweakClass <name> for each tweaker
  --width <w> --height <h>
  join arguments, --demo for demo sessions
```

ForgeWrapper properties, from its public README: `-Dforgewrapper.librariesDir=<Libraries/>`, `-Dforgewrapper.installer=<path of the mavenFiles entry whose classifier is installer>`, `-Dforgewrapper.minecraft=<client.jar path>`.

Join arguments: for a server, with trait `feature:is_quick_play_multiplayer` use `--quickPlayMultiplayer <host>:<port>`, else `--server <host> --port <port>`. For a world, with trait `feature:is_quick_play_singleplayer` use `--quickPlaySingleplayer <world folder>`.

Before joining a server whose port is the default 25565, look up the SRV record `_minecraft._tcp.<host>` with `DNSServiceQueryRecord` (dnssd). When a record exists, use its target and port (lowest priority, then highest weight). When it does not, keep the host and 25565.

Working directory: instance `Minecraft/`. Environment: the current environment without `JAVA_HOME`, `JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`, `JDK_JAVA_OPTIONS` and `CLASSPATH`, plus `settings.environment` and the instance `environment`. Standard input is `/dev/null`.

Read standard output and standard error line by line and send each line as a log event. Replace the access token, the session value and the profile ID in every log line with `<ACCESS TOKEN>`, `<SESSION>` and `<PROFILE ID>`. Mirror launcher log lines to `os.Logger` (subsystem = bundle identifier, category `Launch`) with `.public` privacy after censoring. Detect the level of game lines from markers such as `/WARN]`, `/ERROR]`, `/FATAL]`, `/INFO]`.

Exit: stopping the game on purpose returns its exit code. Exit code 0 returns 0. Any other exit code is a "Game crashed" error that includes the code.

### Forge and NeoForge installer phase

When the main class is ForgeWrapper, the first launch of a Forge or NeoForge version runs the Forge installer's processors inside the game process before Minecraft starts. Facts from the public sources (ForgeWrapper `Installer.java`, MinecraftForge/Installer `PostProcessors.java` on branch `2.0`):

- Installer progress is written to standard output as plain lines without timestamps (for example `JVM info: …`, `  Cache Hit!`, `  Output: … Checksum Validated: …`).
- When a processor throws, the installer prints the stack trace to standard error, then shows a Swing `JOptionPane` error dialog, and only after the dialog closes prints the error message to standard output. Other failures (missing processor jar, missing dependencies, invalid outputs) show the dialog without printing anything first.
- The dialog cannot appear when the JVM runs with `-XstartOnFirstThread`, so the process waits forever. There is no system property that turns the dialog off.

GoldenApple handles this phase as follows:

1. **Phase detection.** For a ForgeWrapper launch, the installer phase starts with the process. It ends at the first output line that is a game log line: one that starts with a `[HH:MM:SS]` time stamp followed by ` [`, or that contains `ModLauncher running`. Verify the end marker against a real Forge 1.20.1 and NeoForge 1.21.1 launch and adjust it if needed.
2. **Log capture.** Tag every line of the installer phase with the log source `installer` in `LaunchEvent.log`. Write the installer phase lines (both streams, in order) to `Instances/<Name>/Logs/Forge Installer.log`, replacing the file of the previous launch. Write the whole output of the last launch, launcher lines included, to `Instances/<Name>/Logs/Latest Launch.log`. Censor both files like the log events. Add `Logs/` to the instance folder layout. Public API: `func launchLog(of instance: Instance, kind: LaunchLogKind) throws -> String?` with `LaunchLogKind` `forgeInstaller` and `latestLaunch`.
3. **Hang detection.** During the installer phase, when no output line has arrived for 20 seconds, send `SIGQUIT` to the process. A HotSpot JVM then prints a thread dump to standard output and keeps running. Do not show thread dump lines as normal log events (tag them `diagnostic`), but keep them in `Forge Installer.log` under a `--- Thread dump ---` header. When the dump contains a frame of `javax.swing.JOptionPane` or `net.minecraftforge.installer.actions.PostProcessors.error`, the installer has failed: terminate the process (SIGTERM, then SIGKILL after 10 seconds) and throw `LauncherError.forgeInstallerFailed`. When it does not, keep waiting and check again after the next 20 quiet seconds. As a backstop, fail the same way when the installer phase lasts longer than 15 minutes.
4. **The error.** `forgeInstallerFailed` carries the loader name and version, the Minecraft version, the last stack trace from the installer phase (the block that starts at a line with `Exception` or `Error:` and its following `at …` and `Caused by:` lines), and the path of `Forge Installer.log`. Its message says the installer failed, names the loader version, and shows the stack trace summary when there is one. When there is none, it says the installer stopped at an error dialog that macOS cannot show and points to the log file.

### Error reports

Every error that `launch`, `createInstance`, `install`, `installModpack` and `importModpack` throw must be easy to copy for a bug report. Add `struct ErrorReport: Sendable` with `title: String`, `message: String`, `details: String?` (for example the installer stack trace or the tail of the installer log, at most 200 lines) and `text: String`. `text` is the full plain-text report for the pasteboard: the title, the message, the details, and a context block with the GoldenApple version, the macOS version, the instance name, its Minecraft and loader versions, and the selected Java version and path when known. Censor tokens in `text`. Add `static func report(for error: any Error, instance: Instance?) -> ErrorReport` on `GoldenAppleLauncher` (or an equivalent public function). The library does not touch the pasteboard. The app copies `report.text`.

## Mods, resource packs, shader packs and modpacks

Content kinds and their game folders: mod (`mods`), resource pack (`resourcepacks`), shader pack (`shaderpacks`), modpack.

A content target is the instance Minecraft version plus its loaders. A Quilt instance also accepts Fabric content. A NeoForge instance on Minecraft 1.20.1 also accepts Forge content.

`Installed Content.json` records what GoldenApple installed: `{ "formatVersion": 1, "entries": [ { "provider", "projectID", "versionID", "title", "versionNumber", "path", "sha1"? } ] }`. `path` is relative to `Minecraft/`. Installing a newer file of the same project deletes the old file.

### Modrinth

API base `https://api.modrinth.com/v2/`, no key. Send the user agent.

- Search: `GET search?query=&facets=[["project_type:mod"],["versions:<mc>"],["categories:fabric","categories:quilt"]]&offset=&limit=&index=relevance`. Hits have `project_id`, `slug`, `title`, `description`, `author`, `downloads`, `icon_url`, `project_type`. Project types: `mod`, `resourcepack`, `shader`, `modpack`. Loader facets only for mods.
- Project: `GET project/<id or slug>`.
- Versions: `GET project/<id>/version?game_versions=["<mc>"]&loaders=["fabric"]`. Each has `id`, `project_id`, `name`, `version_number`, `version_type` (`release`, `beta`, `alpha`), `date_published`, `game_versions`, `loaders`, `dependencies` (`version_id`, `project_id`, `dependency_type`: `required`, `optional`, `incompatible`, `embedded`), and `files` (`url`, `filename`, `primary`, `size`, `hashes.sha1`, `hashes.sha512`). Use the primary file, else the first.
- The best version is the newest `release`, else the newest of any type.
- Install required dependencies too. A dependency with `version_id` uses that version. Otherwise use the best version of `project_id` for the target. Skip projects already installed. Verify SHA-512 when present, else SHA-1.

### CurseForge

API base `https://api.curseforge.com/v1/`, header `x-api-key: <key>`. Without a key, every CurseForge call fails with a message that says to set `curseForgeAPIKey`. Responses wrap data in `{ "data": ... }`.

- Search: `GET mods/search?gameId=432&classId=<class>&searchFilter=&gameVersion=&modLoaderTypes=[4]&index=&pageSize=&sortField=2&sortOrder=desc`. Class IDs: mods 6, resource packs 12, shader packs 6552, modpacks 4471. Loader types: Forge 1, Fabric 4, Quilt 5, NeoForge 6. `sortField` 2 is popularity. Results have `id`, `slug`, `name`, `summary`, `authors[].name`, `downloadCount`, `logo.thumbnailUrl`, `links.websiteUrl`, `classId`. `pagination.totalCount` is the total.
- Files: `GET mods/<id>/files?gameVersion=&modLoaderType=&pageSize=10000`, `GET mods/<id>/files/<fileId>`, `POST mods/files` with `{ "fileIds": [...] }`, `POST mods` with `{ "modIds": [...] }`.
- File fields: `id`, `modId`, `displayName`, `fileName`, `fileDate`, `releaseType` (1 release, 2 beta, 3 alpha), `downloadUrl` (can be null), `fileLength`, `gameVersions` (Minecraft versions and loader names mixed), `hashes` (`algo` 1 is SHA-1, 2 is MD5), `dependencies` (`modId`, `relationType`: 3 required, 2 optional).
- A file with a null `downloadUrl` cannot be downloaded by the launcher. Return it as a blocked download with the page `<links.websiteUrl>/download/<fileId>` and the destination path, so the user can download it by hand.

### Essential

Essential is the Modrinth project `k2ZPuTBm` (slug `essential`). It is published for Fabric, Forge and NeoForge. Installing Essential into an instance without a loader first adds the recommended Fabric loader version and resolves components.

### Modrinth modpacks (`.mrpack`)

A zip with `modrinth.index.json`: `{ "formatVersion": 1, "game": "minecraft", "versionId", "name", "summary"?, "files": [ { "path", "hashes": { "sha1", "sha512" }, "env"?: { "client": "required" | "optional" | "unsupported", "server" }, "downloads": [urls], "fileSize" } ], "dependencies": { "minecraft", "fabric-loader"?, "quilt-loader"?, "forge"?, "neoforge"? } }`, plus `overrides/` and `client-overrides/` folders.

Create the instance from `dependencies`. Skip files whose `env.client` is `unsupported`. Reject any path that is absolute or contains `..`. Download each file to `Minecraft/<path>` with its SHA-512. Copy `overrides/` and then `client-overrides/` into `Minecraft/`, replacing files. When any step fails, delete the new instance.

### CurseForge modpacks

A zip with `manifest.json`: `{ "manifestType": "minecraftModpack", "manifestVersion": 1, "name", "version", "minecraft": { "version", "modLoaders": [ { "id": "forge-47.2.0" | "neoforge-21.1.77" | "fabric-0.16.9" | "quilt-0.26.0", "primary" } ] }, "files": [ { "projectID", "fileID", "required" } ], "overrides": "overrides" }`. A NeoForge ID can also look like `neoforge-1.20.1-47.1.100`; drop the `1.20.1-` part. Install required files to the folder of their project class. Report blocked files. Copy the overrides folder into `Minecraft/`.

## Public API

The app uses these entry points. Keep names and shapes. Everything else is internal.

```swift
actor GoldenAppleLauncher {
    init(configuration: GoldenAppleConfiguration = .default, dataRoot: URL? = nil)
    nonisolated let configuration: GoldenAppleConfiguration
    nonisolated let paths: LauncherPaths

    func prepare() async throws                      // create folders, empty Cache/Downloads, load settings and accounts
    func settings() -> LauncherSettings
    func updateSettings(_ change: @Sendable (inout LauncherSettings) -> Void) throws
    func microsoftClientID() -> String

    // Versions
    func minecraftVersions(includeSnapshots: Bool) async throws -> [GameVersion]
    func loaderVersions(_ loader: ModLoader, minecraftVersion: String) async throws -> [LoaderVersion]

    // Instances
    func instances() throws -> [Instance]
    func createInstance(name: String, minecraftVersion: String, loader: ModLoader?, loaderVersion: String?) async throws -> Instance
    func setMinecraftVersion(_ version: String, for instance: Instance) async throws
    func setLoader(_ loader: ModLoader?, version: String?, for instance: Instance) async throws
    func renameInstance(_ instance: Instance, to name: String) throws -> Instance
    func deleteInstance(_ instance: Instance) throws          // moves the folder to the Trash
    func components(of instance: Instance) throws -> [InstanceComponent]

    // Accounts
    func accounts() -> [Account]
    func defaultAccount() -> Account?
    func setDefaultAccount(_ account: Account?) throws
    func signInWithMicrosoft() async throws -> Account        // presents ASWebAuthenticationSession on the main actor, anchored to the key window
    func signInWithDeviceCode(onCode: @Sendable (DeviceCode) -> Void) async throws -> Account
    func addOfflineAccount(name: String) throws -> Account
    func removeAccount(_ account: Account) throws

    // Java
    func javaInstallations() async -> [JavaInstallation]

    // Launch
    func launch(_ instance: Instance, account: Account?, mode: LaunchMode, join: JoinTarget?,
                events: @escaping @Sendable (LaunchEvent) -> Void,
                subprogress: consuming Subprogress?) async throws -> Int32
    func stop(_ instance: Instance) async
    func isRunning(_ instance: Instance) -> Bool

    // Content
    func search(_ query: String, provider: ContentProvider, kind: ContentKind, for instance: Instance?,
                offset: Int, limit: Int) async throws -> ContentSearchPage
    func versions(of project: ContentProject, for instance: Instance) async throws -> [ContentVersion]
    func install(_ project: ContentProject, version: ContentVersion?, into instance: Instance,
                 subprogress: consuming Subprogress?) async throws -> ContentInstallResult
    func installEssential(into instance: Instance, subprogress: consuming Subprogress?) async throws -> ContentInstallResult
    func installedContent(of instance: Instance) throws -> [InstalledContentEntry]
    func uninstall(_ entry: InstalledContentEntry, from instance: Instance) throws
    func installModpack(_ project: ContentProject, version: ContentVersion?, name: String?,
                        subprogress: consuming Subprogress?) async throws -> ModpackResult
    func importModpack(at file: URL, name: String?, subprogress: consuming Subprogress?) async throws -> ModpackResult
}
```

Value types (all `Sendable`): `GameVersion` (`id`, `type`, `releaseTime`), `LoaderVersion` (`version`, `isRecommended`, `releaseTime`), `Instance` (`id` folder name, `name`, `folder`, `gameFolder`, `minecraftVersion`, `loader`, `loaderVersion`, `lastPlayed`), `InstanceComponent`, `ModLoader` (`fabric`, `quilt`, `forge`, `neoForge`), `Account` (`id`, `kind`, `profileName`, `profileID`, `ownsMinecraft`, `needsSignIn`), `DeviceCode` (`userCode`, `verificationURL`, `expiresAt`), `JavaInstallation` (`path`, `version`, `major`, `vendor`), `LaunchMode` (`online`, `offline(playerName: String?)`, `demo(playerName: String)`), `JoinTarget` (`server(host: String, port: UInt16)`, `world(String)`), `LaunchEvent` (`log(LogLine)`, `status(String)`, `gameStarted(processID: Int32)`, `gameExited(code: Int32)`), `ContentProvider` (`modrinth`, `curseForge`), `ContentKind`, `ContentProject`, `ContentVersion`, `ContentSearchPage` (`projects`, `totalCount`), `ContentInstallResult` (`installed`, `blocked`), `InstalledContentEntry`, `BlockedDownload` (`title`, `fileName`, `pageURL`, `destination`), `ModpackResult` (`instance`, `blocked`).

Errors: one `LauncherError` enum conforming to `LocalizedError` with messages a player can act on.

## Folder structure of the code

```
GoldenApple/Launcher/
├── GoldenAppleLauncher.swift          public actor and its extensions per area
├── Core/                              configuration, paths, settings, errors, logging
├── Support/                           file system, hashing, JSON, version comparison, processes, archives, Keychain
├── Network/                           HTTP client, HTTP cache, download queue
├── Metadata/                          metadata client and models
├── Game/                              library rules, profile merge, components, resolver, assets, instances
├── Java/                              check, discovery, runtime install, selection
├── Accounts/                          Microsoft, Xbox, Minecraft services, offline, store, Keychain
├── Launch/                            command builder, game process, SRV lookup, launch pipeline
└── Content/                           Modrinth, CurseForge, installer, modpacks
```
