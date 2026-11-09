import Foundation
import os

/// One file to download.
nonisolated struct DownloadItem: Hashable, Sendable {
    let url: URL
    let destination: URL
    var checksum: Checksum?
    var size: Int64?
    /// Accept an existing file when its size matches, without hashing it. Used for asset objects.
    var skipsWhenSizeMatches = false
}

/// Downloads files in parallel. Each file goes to `Cache/Downloads/<uuid>.part` first,
/// is checked against its hash, then moves into place.
nonisolated struct DownloadQueue: Sendable {
    let http: HTTPClient
    let stagingFolder: URL
    let settings: SettingsStore

    private enum Outcome: Sendable {
        case finished(DownloadItem)
        case failed(DownloadFailure)
    }

    /// Downloads every item that is missing or damaged, up to `concurrentDownloads` at a time.
    /// All items are tried. When some fail, one `downloadsFailed` error lists them all.
    func download(_ items: [DownloadItem], subprogress: consuming Subprogress? = nil) async throws {
        let uniqueItems = Self.removingDuplicateDestinations(items)
        let progress = ProgressManager.start(subprogress, totalCount: uniqueItems.count)
        progress.totalFileCount = uniqueItems.count
        progress.totalByteCount = uniqueItems.reduce(0) { $0 + UInt64(max($1.size ?? 0, 0)) }

        let limit = max(1, settings.current.concurrentDownloads)
        var failures: [DownloadFailure] = []
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            var remaining = uniqueItems.makeIterator()
            for _ in 0..<limit {
                guard let item = remaining.next() else {
                    break
                }
                group.addTask { try await fetch(item) }
            }
            while let outcome = try await group.next() {
                switch outcome {
                case .finished(let item):
                    progress.completedByteCount += UInt64(max(item.size ?? 0, 0))
                case .failed(let failure):
                    failures.append(failure)
                }
                progress.completedFileCount += 1
                progress.complete(count: 1)
                if let item = remaining.next() {
                    group.addTask { try await fetch(item) }
                }
            }
        }

        guard failures.isEmpty else {
            throw LauncherError.downloadsFailed(failures.sorted { $0.destination.path < $1.destination.path })
        }
    }

    /// Whether `item.destination` already holds the expected file.
    static func isValid(_ item: DownloadItem) async -> Bool {
        guard FileSystem.exists(item.destination) else {
            return false
        }
        let sizeMatches = item.size.map { FileSystem.fileSize(item.destination) == $0 }
        if item.skipsWhenSizeMatches, sizeMatches == true {
            return true
        }
        if let checksum = item.checksum {
            return await checksum.matches(item.destination)
        }
        return sizeMatches ?? true
    }

    @concurrent
    private func fetch(_ item: DownloadItem) async throws -> Outcome {
        do {
            if await Self.isValid(item) {
                return .finished(item)
            }
            let temporaryFile = try await http.download(from: item.url)
            let partFile = stagingFolder.appending(path: "\(UUID().uuidString).part")
            defer { try? FileSystem.removeIfPresent(partFile) }
            try FileSystem.move(temporaryFile, to: partFile)
            try await verify(partFile, for: item)
            try FileSystem.move(partFile, to: item.destination)
            return .finished(item)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            LauncherLog.network.error("Download failed: \(item.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(DownloadFailure(url: item.url, destination: item.destination, reason: error.localizedDescription))
        }
    }

    private func verify(_ partFile: URL, for item: DownloadItem) async throws {
        if let checksum = item.checksum {
            do {
                try await checksum.verify(partFile)
            } catch LauncherError.checksumMismatch(_, let expected, let actual) {
                throw LauncherError.checksumMismatch(file: item.destination.lastPathComponent, expected: expected, actual: actual)
            }
        } else if let size = item.size, let actualSize = FileSystem.fileSize(partFile), size != actualSize {
            throw LauncherError.checksumMismatch(file: item.destination.lastPathComponent, expected: "\(size) bytes", actual: "\(actualSize) bytes")
        }
    }

    private static func removingDuplicateDestinations(_ items: [DownloadItem]) -> [DownloadItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.destination.standardizedFileURL.path).inserted }
    }
}
