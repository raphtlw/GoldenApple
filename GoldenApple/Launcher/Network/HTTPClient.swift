import Foundation
import os

/// The launcher's only `URLSession`. Sends the user agent, uses no URL cache,
/// and retries network errors twice. HTTP error statuses are not retried.
nonisolated final class HTTPClient: Sendable {
    private static let retryCount = 2
    private static let retryDelay = Duration.seconds(1)

    private let session: URLSession

    init(userAgent: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: configuration)
    }

    /// Sends a request and returns the body and response for any HTTP status.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withRetries(for: request) {
            let (data, response) = try await self.session.data(for: request)
            return (data, try Self.httpResponse(response, for: request))
        }
    }

    /// Sends a request and returns the body. A status outside 200...299 is an error.
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        try Self.requireSuccess(response, for: request)
        return data
    }

    func data(from url: URL) async throws -> Data {
        try await data(for: URLRequest(url: url))
    }

    /// Downloads to a temporary file that the caller must move or delete.
    /// A status outside 200...299 is an error.
    func download(from url: URL) async throws -> URL {
        let request = URLRequest(url: url)
        return try await withRetries(for: request) {
            let (file, response) = try await self.session.download(for: request)
            do {
                try Self.requireSuccess(try Self.httpResponse(response, for: request), for: request)
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
            return file
        }
    }

    private func withRetries<Value>(for request: URLRequest, _ operation: () async throws -> Value) async throws -> Value {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as URLError where error.code != .cancelled {
                guard attempt < Self.retryCount else {
                    throw LauncherError.networkFailure(url: request.url ?? URL(filePath: "/"), reason: error.localizedDescription)
                }
                attempt += 1
                LauncherLog.network.info("Retrying \(request.url?.absoluteString ?? "", privacy: .public) after: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: Self.retryDelay)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            }
        }
    }

    private static func httpResponse(_ response: URLResponse, for request: URLRequest) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw LauncherError.networkFailure(url: request.url ?? URL(filePath: "/"), reason: "The server did not answer with HTTP.")
        }
        return response
    }

    private static func requireSuccess(_ response: HTTPURLResponse, for request: URLRequest) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw LauncherError.httpStatus(url: request.url ?? URL(filePath: "/"), statusCode: response.statusCode)
        }
    }
}
