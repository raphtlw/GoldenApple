import Foundation
import Synchronization

/// The contents of `Accounts.json`.
nonisolated struct AccountList: Codable, Equatable, Sendable {
    var defaultAccountID: String?
    var accounts: [AccountRecord] = []

    func record(id: String) -> AccountRecord? {
        accounts.first { $0.id == id }
    }

    /// Replaces the record with the same ID, or appends it.
    mutating func save(_ record: AccountRecord) {
        if let index = accounts.firstIndex(where: { $0.id == record.id }) {
            accounts[index] = record
        } else {
            accounts.append(record)
        }
    }
}

/// Holds the account list in memory and writes every change to `Accounts.json`.
nonisolated final class AccountStore: Sendable {
    private let file: URL
    private let state = Mutex(AccountList())

    init(file: URL) {
        self.file = file
    }

    var list: AccountList {
        state.withLock { $0 }
    }

    func record(id: String) -> AccountRecord? {
        list.record(id: id)
    }

    /// Reads `Accounts.json`. A missing file means no accounts.
    func load() throws {
        guard FileSystem.exists(file) else {
            state.withLock { $0 = AccountList() }
            return
        }
        let loaded = try JSONFiles.readOwnFile(AccountList.self, from: file)
        state.withLock { $0 = loaded }
    }

    /// Changes the list and writes it. When writing fails, the list in memory stays unchanged.
    @discardableResult
    func update<Result>(_ change: (inout AccountList) throws -> Result) throws -> Result {
        try state.withLock { list in
            var changed = list
            let result = try change(&changed)
            if changed != list {
                try JSONFiles.writeOwnFile(changed, to: file)
                list = changed
            }
            return result
        }
    }
}

/// Microsoft account secrets in the Keychain: service `GoldenApple Accounts`, account = the account ID.
nonisolated struct AccountSecretStore: Sendable {
    static let service = "GoldenApple Accounts"

    private let keychain = KeychainStore(service: service)

    /// Nil when no item exists. An item that cannot be decoded also counts as missing.
    func secrets(for accountID: String) throws -> AccountSecrets? {
        guard let data = try keychain.data(for: accountID) else {
            return nil
        }
        return try? JSONFiles.makeDecoder().decode(AccountSecrets.self, from: data)
    }

    func save(_ secrets: AccountSecrets, for accountID: String) throws {
        try keychain.setData(try JSONFiles.makeEncoder().encode(secrets), for: accountID)
    }

    func delete(for accountID: String) throws {
        try keychain.delete(accountID)
    }
}
