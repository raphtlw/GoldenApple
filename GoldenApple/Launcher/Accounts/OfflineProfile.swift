import CryptoKit
import Foundation

/// Player names and profile IDs for sessions without Microsoft sign-in.
nonisolated enum OfflineProfile {
    private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

    /// 1 to 16 letters, digits or underscores.
    static func isValidName(_ name: String) -> Bool {
        (1...16).contains(name.unicodeScalars.count) && name.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }

    static func validate(_ name: String) throws {
        guard isValidName(name) else {
            throw LauncherError.invalidPlayerName(name)
        }
    }

    /// The version 3 UUID made from the MD5 of `OfflinePlayer:<name>`, as 32 lowercase hexadecimal digits.
    static func profileID(for name: String) -> String {
        var bytes = Array(Insecure.MD5.hash(data: Data("OfflinePlayer:\(name)".utf8)))
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
