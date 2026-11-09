import Foundation

/// Finds arm64 Java installations on this Mac.
nonisolated struct JavaDiscovery: Sendable {
    let paths: LauncherPaths

    /// Every usable `aarch64` Java, newest version first.
    @concurrent
    func installations() async -> [JavaInstallation] {
        let candidates = await candidateBinaries()
        let results = await withTaskGroup(of: JavaCheckResult?.self) { group in
            for binary in candidates {
                group.addTask { await JavaChecker.check(binary) }
            }
            var results: [JavaCheckResult] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }
        return results
            .filter(\.isARM64)
            .compactMap(\.installation)
            .sorted { lhs, rhs in
                if let left = JavaVersion(lhs.version), let right = JavaVersion(rhs.version), left != right {
                    return left > right
                }
                return lhs.path.path < rhs.path.path
            }
    }

    /// Existing `java` binaries, without duplicates that resolve to the same file.
    func candidateBinaries() async -> [URL] {
        let homeLibrary = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Java/JavaVirtualMachines")
        var binaries: [URL] = []
        for runtime in subfolders(of: paths.java) {
            binaries.append(runtime.appending(path: "bin/java"))
            binaries.append(runtime.appending(path: "Contents/Home/bin/java"))
        }
        for machines in [URL(filePath: "/Library/Java/JavaVirtualMachines"), homeLibrary] {
            for machine in subfolders(of: machines) {
                binaries.append(machine.appending(path: "Contents/Home/bin/java"))
            }
        }
        binaries += await javaHomeBinaries()

        var seen = Set<String>()
        return binaries.filter { binary in
            FileSystem.exists(binary) && seen.insert(binary.resolvingSymlinksInPath().path).inserted
        }
    }

    /// Homes listed by `/usr/libexec/java_home -V`, as `bin/java` paths.
    private func javaHomeBinaries() async -> [URL] {
        guard let result = try? await ProcessRunner.run(URL(filePath: "/usr/libexec/java_home"), arguments: ["-V"], timeout: .seconds(15)) else {
            return []
        }
        let lines = (result.standardErrorText + "\n" + result.standardOutputText).split(whereSeparator: \.isNewline)
        return lines.compactMap { line in
            // Lines look like: 21.0.2 (arm64) "Vendor" - "Name" /Library/Java/JavaVirtualMachines/x.jdk/Contents/Home
            let afterQuotes = line.lastIndex(of: "\"").map { line[line.index(after: $0)...] } ?? line[...]
            let home = afterQuotes.trimmingCharacters(in: .whitespaces)
            guard home.hasPrefix("/") else {
                return nil
            }
            return URL(filePath: home, directoryHint: .isDirectory).appending(path: "bin/java")
        }
    }

    private func subfolders(of folder: URL) -> [URL] {
        ((try? FileSystem.contents(of: folder)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
    }
}
