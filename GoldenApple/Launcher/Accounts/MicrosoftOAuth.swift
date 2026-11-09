import CryptoKit
import Foundation

nonisolated struct MicrosoftTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
}

/// OAuth 2.0 with the Microsoft identity platform for personal accounts:
/// authorization code with PKCE, device code, and refresh.
nonisolated struct MicrosoftOAuth: Sendable {
    struct AuthorizationRequest: Sendable {
        let url: URL
        let state: String
        let codeVerifier: String
    }

    struct DeviceCodeGrant: Sendable {
        let deviceCode: String
        let code: DeviceCode
        let interval: Duration
    }

    /// What the token endpoint answered.
    private enum TokenOutcome {
        case tokens(MicrosoftTokens)
        case refused(code: String, description: String)
    }

    static let scope = "XboxLive.SignIn XboxLive.offline_access"
    private static let endpoint = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/")!
    private static let serviceName = "Microsoft sign-in"
    private static let slowDownStep = Duration.seconds(5)

    let http: HTTPClient
    let clientID: String
    let redirectURI: String

    var callbackScheme: String {
        URL(string: redirectURI)?.scheme ?? "goldenapple"
    }

    // MARK: Authorization code with PKCE

    func authorizationRequest() -> AuthorizationRequest {
        let verifier = Self.randomURLSafeText(byteCount: 32)
        let state = Self.randomURLSafeText(byteCount: 16)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(url: Self.endpoint.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = FormEncoding.encode([
            "client_id": clientID,
            "response_type": "code",
            "redirect_uri": redirectURI,
            "scope": Self.scope,
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "prompt": "select_account",
        ])
        return AuthorizationRequest(url: components.url!, state: state, codeVerifier: verifier)
    }

    /// Reads the code from the redirect URL after checking `state`.
    func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error") {
            if error == "access_denied" {
                throw LauncherError.signInCancelled
            }
            throw LauncherError.microsoftSignInFailed(code: error, description: Self.firstLine(value("error_description")))
        }
        guard value("state") == expectedState else {
            throw LauncherError.microsoftSignInFailed(code: "state_mismatch", description: "The answer from Microsoft does not belong to this sign-in. Try again.")
        }
        guard let code = value("code").nonEmpty else {
            throw LauncherError.microsoftSignInFailed(code: "missing_code", description: "Microsoft did not send an authorization code.")
        }
        return code
    }

    func redeem(code: String, codeVerifier: String) async throws -> MicrosoftTokens {
        try await tokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
            "client_id": clientID,
            "scope": Self.scope,
        ])
    }

    // MARK: Refresh

    /// Keeps the old refresh token when Microsoft sends no new one.
    func refresh(_ refreshToken: String) async throws -> MicrosoftTokens {
        let refreshed = try await tokens([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": Self.scope,
        ])
        return MicrosoftTokens(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken ?? refreshToken)
    }

    // MARK: Device code

    func requestDeviceCode() async throws -> DeviceCodeGrant {
        let request = URLRequest.formPost(Self.endpoint.appending(path: "devicecode"), fields: ["client_id": clientID, "scope": Self.scope])
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(from: data, response: response)
        }
        let body = try ServiceResponse.decode(DeviceCodeResponse.self, from: data, service: Self.serviceName)
        guard let verificationURL = URL(string: body.verificationURI) else {
            throw LauncherError.unexpectedResponse(service: Self.serviceName, reason: "invalid verification address \(body.verificationURI)")
        }
        let code = DeviceCode(userCode: body.userCode, verificationURL: verificationURL, expiresAt: Date().addingTimeInterval(TimeInterval(body.expiresIn)))
        return DeviceCodeGrant(deviceCode: body.deviceCode, code: code, interval: .seconds(body.interval ?? 5))
    }

    /// Polls the token endpoint every `interval` until the player finishes the sign-in or the code expires.
    func waitForTokens(_ grant: DeviceCodeGrant) async throws -> MicrosoftTokens {
        var interval = grant.interval
        while true {
            try await Task.sleep(for: interval)
            guard Date() < grant.code.expiresAt else {
                throw LauncherError.deviceCodeExpired
            }
            let outcome = try await requestTokens([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": clientID,
                "device_code": grant.deviceCode,
            ])
            switch outcome {
            case .tokens(let tokens):
                return tokens
            case .refused("authorization_pending", _):
                continue
            case .refused("slow_down", _):
                interval += Self.slowDownStep
            case .refused("expired_token", _), .refused("code_expired", _):
                throw LauncherError.deviceCodeExpired
            case .refused("authorization_declined", _), .refused("access_denied", _):
                throw LauncherError.signInCancelled
            case .refused(let code, let description):
                throw LauncherError.microsoftSignInFailed(code: code, description: description)
            }
        }
    }

    // MARK: Token endpoint

    private func tokens(_ fields: KeyValuePairs<String, String>) async throws -> MicrosoftTokens {
        switch try await requestTokens(fields) {
        case .tokens(let tokens):
            return tokens
        case .refused(let code, let description):
            throw LauncherError.microsoftSignInFailed(code: code, description: description)
        }
    }

    private func requestTokens(_ fields: KeyValuePairs<String, String>) async throws -> TokenOutcome {
        let (data, response) = try await http.send(.formPost(Self.endpoint.appending(path: "token"), fields: fields))
        let body = try? JSONDecoder().decode(TokenResponse.self, from: data)
        if let error = body?.error {
            return .refused(code: error, description: Self.firstLine(body?.errorDescription))
        }
        try ServiceResponse.requireSuccess(response)
        guard let accessToken = body?.accessToken.nonEmpty else {
            throw LauncherError.unexpectedResponse(service: Self.serviceName, reason: "no access token")
        }
        return .tokens(MicrosoftTokens(accessToken: accessToken, refreshToken: body?.refreshToken.nonEmpty))
    }

    private static func error(from data: Data, response: HTTPURLResponse) -> LauncherError {
        guard let body = try? JSONDecoder().decode(TokenResponse.self, from: data), let code = body.error else {
            return .httpStatus(url: response.url ?? endpoint, statusCode: response.statusCode)
        }
        return .microsoftSignInFailed(code: code, description: firstLine(body.errorDescription))
    }

    // MARK: Helpers

    /// Microsoft error descriptions add trace and correlation IDs on later lines.
    private static func firstLine(_ text: String?) -> String {
        text?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func randomURLSafeText(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }
}

nonisolated private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let error: String?
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case error
        case errorDescription = "error_description"
    }
}

nonisolated private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int?

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}
