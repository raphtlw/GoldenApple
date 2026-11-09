import AppKit
import AuthenticationServices
import Foundation
import Synchronization

/// Shows a web sign-in page with `ASWebAuthenticationSession`, anchored to the key window,
/// and returns the redirect URL that uses the callback scheme.
@MainActor
final class BrowserSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    private init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    static func callbackURL(opening url: URL, callbackScheme: String) async throws -> URL {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            throw LauncherError.signInWindowUnavailable
        }
        let signIn = BrowserSignIn(anchor: window)
        return try await withTaskCancellationHandler {
            try await signIn.run(url, callbackScheme: callbackScheme)
        } onCancel: {
            Task { @MainActor in signIn.cancel() }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    private func run(_ url: URL, callbackScheme: String) async throws -> URL {
        try Task.checkCancellation()
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let resume = OnceContinuation(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { @Sendable callbackURL, error in
                if let callbackURL {
                    resume.resume(with: .success(callbackURL))
                } else {
                    resume.resume(with: .failure(Self.launcherError(for: error)))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                resume.resume(with: .failure(LauncherError.signInWindowUnavailable))
            }
        }
    }

    private func cancel() {
        session?.cancel()
    }

    nonisolated private static func launcherError(for error: (any Error)?) -> LauncherError {
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            return .signInCancelled
        }
        return .microsoftSignInFailed(code: "browser", description: error?.localizedDescription ?? "")
    }
}

/// Resumes a continuation at most once, because the session can report a failure after `start()` returned false.
nonisolated private final class OnceContinuation<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<Value, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}
