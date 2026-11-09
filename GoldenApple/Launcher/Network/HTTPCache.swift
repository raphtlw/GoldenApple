import Foundation
import os

/// Conditional GET requests with `ETag` and `Last-Modified`. The validators for each URL are kept in `Cache/HTTP Cache.json`.
actor HTTPCache {
    private struct Entry: Codable {
        var etag: String?
        var lastModified: String?
    }

    private struct Store: Codable {
        var entries: [String: Entry] = [:]
    }

    private let http: HTTPClient
    private let storeFile: URL
    private var store: Store?

    init(http: HTTPClient, storeFile: URL) {
        self.http = http
        self.storeFile = storeFile
    }

    /// Fetches `url` and keeps the body in `file`. When the server answers 304, the body of `file` is returned.
    func fetch(_ url: URL, cachedIn file: URL) async throws -> Data {
        var request = URLRequest(url: url)
        let cachedEntry = FileSystem.exists(file) ? loadStore().entries[url.absoluteString] : nil
        if let cachedEntry {
            request.setValue(cachedEntry.etag, forHTTPHeaderField: "If-None-Match")
            request.setValue(cachedEntry.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await http.send(request)
        if response.statusCode == 304, cachedEntry != nil {
            LauncherLog.network.debug("Not modified: \(url.absoluteString, privacy: .public)")
            return try Data(contentsOf: file)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LauncherError.httpStatus(url: url, statusCode: response.statusCode)
        }

        try FileSystem.writeAtomically(data, to: file)
        let entry = Entry(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
        try save(entry, for: url)
        return data
    }

    private func loadStore() -> Store {
        if let store {
            return store
        }
        var loaded = Store()
        if FileSystem.exists(storeFile) {
            do {
                loaded = try JSONFiles.readOwnFile(Store.self, from: storeFile)
            } catch {
                LauncherLog.network.error("Ignoring the HTTP cache file: \(error.localizedDescription, privacy: .public)")
            }
        }
        store = loaded
        return loaded
    }

    private func save(_ entry: Entry, for url: URL) throws {
        var updated = loadStore()
        if entry.etag == nil && entry.lastModified == nil {
            updated.entries[url.absoluteString] = nil
        } else {
            updated.entries[url.absoluteString] = entry
        }
        store = updated
        try JSONFiles.writeOwnFile(updated, to: storeFile)
    }
}
