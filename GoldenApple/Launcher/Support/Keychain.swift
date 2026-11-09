import Foundation
import Security

/// Generic password items of one Keychain service, keyed by account name.
nonisolated struct KeychainStore: Sendable {
    let service: String

    /// The stored data, or nil when no item exists.
    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        try Self.check(status)
        return result as? Data
    }

    /// Creates the item or replaces its data.
    func setData(_ data: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            try Self.check(updateStatus)
            return
        }
        var newItem = query
        newItem[kSecValueData] = data
        newItem[kSecAttrLabel] = service
        try Self.check(SecItemAdd(newItem as CFDictionary, nil))
    }

    /// Deletes the item. A missing item is not an error.
    func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status != errSecItemNotFound else {
            return
        }
        try Self.check(status)
    }

    private func baseQuery(for account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw LauncherError.keychainFailure(status: status)
        }
    }
}
