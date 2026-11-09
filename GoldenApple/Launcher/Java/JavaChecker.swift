import Foundation
import os

/// A Java binary that GoldenApple can use.
nonisolated struct JavaInstallation: Hashable, Identifiable, Sendable {
    let path: URL
    let version: String
    let major: Int
    let vendor: String

    var id: String { path.path }
}

/// What `java -XshowSettings:properties -version` reported.
nonisolated struct JavaCheckResult: Codable, Hashable, Sendable {
    let path: String
    let version: String
    let vendor: String
    let architecture: String

    var isARM64: Bool {
        architecture == "aarch64"
    }

    /// Nil when the version cannot be parsed.
    var installation: JavaInstallation? {
        guard let parsed = JavaVersion(version) else {
            return nil
        }
        return JavaInstallation(path: URL(filePath: path), version: version, major: parsed.major, vendor: vendor)
    }
}

/// A cached check, valid while the binary's path and modification time are unchanged.
nonisolated struct JavaCheckRecord: Codable, Hashable, Sendable {
    let signature: String
    let result: JavaCheckResult
}

/// Runs a Java binary to read its version, vendor and architecture.
nonisolated enum JavaChecker {
    private static let timeout = Duration.seconds(15)

    /// Nil when the binary fails, times out or does not report the needed properties.
    static func check(_ binary: URL) async -> JavaCheckResult? {
        do {
            let result = try await ProcessRunner.run(binary, arguments: ["-XshowSettings:properties", "-version"], timeout: timeout)
            guard result.exitCode == 0 else {
                LauncherLog.java.info("Java check failed for \(binary.path, privacy: .public) with exit code \(result.exitCode)")
                return nil
            }
            return parse(result.standardErrorText, path: binary.path)
        } catch {
            LauncherLog.java.info("Java check failed for \(binary.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reuses `cached` when its signature still matches the binary. Returns the result and the record to store.
    static func check(_ binary: URL, cached: JavaCheckRecord?) async -> (result: JavaCheckResult, record: JavaCheckRecord)? {
        guard let signature = signature(of: binary) else {
            return nil
        }
        if let cached, cached.signature == signature {
            return (cached.result, cached)
        }
        guard let result = await check(binary) else {
            return nil
        }
        return (result, JavaCheckRecord(signature: signature, result: result))
    }

    /// The binary path and its modification time. Nil when the file does not exist.
    static func signature(of binary: URL) -> String? {
        guard FileSystem.exists(binary), let modified = FileSystem.modificationDate(binary) else {
            return nil
        }
        return "\(binary.path)|\(modified.timeIntervalSince1970)"
    }

    /// Reads `    key = value` lines.
    static func parse(_ output: String, path: String) -> JavaCheckResult? {
        var properties: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.range(of: " = ") else {
                continue
            }
            let key = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            properties[key] = value
        }
        guard let version = properties["java.version"], let vendor = properties["java.vendor"], let architecture = properties["os.arch"] else {
            return nil
        }
        return JavaCheckResult(path: path, version: version, vendor: vendor, architecture: architecture)
    }
}
