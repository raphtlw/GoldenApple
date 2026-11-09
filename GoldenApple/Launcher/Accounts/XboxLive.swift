import Foundation

/// An Xbox Live token and the user hash (`uhs`) that belongs to it.
nonisolated struct XboxToken: Sendable {
    let token: String
    let userHash: String
}

/// Exchanges a Microsoft access token for an Xbox user token, then for an XSTS token for Minecraft services.
nonisolated struct XboxLive: Sendable {
    private static let userAuthenticationURL = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
    private static let authorizationURL = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
    private static let serviceName = "Xbox Live"

    let http: HTTPClient

    func userToken(microsoftAccessToken: String) async throws -> XboxToken {
        var request = try URLRequest.jsonPost(Self.userAuthenticationURL, body: [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(microsoftAccessToken)",
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT",
        ])
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        let (data, response) = try await http.send(request)
        try ServiceResponse.requireSuccess(response)
        return try Self.token(from: data)
    }

    /// A 401 answer carries an `XErr` code, which becomes `xboxSignInRefused`.
    func minecraftToken(userToken: XboxToken) async throws -> XboxToken {
        let request = try URLRequest.jsonPost(Self.authorizationURL, body: [
            "Properties": [
                "SandboxId": "RETAIL",
                "UserTokens": [userToken.token],
            ],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT",
        ])
        let (data, response) = try await http.send(request)
        if response.statusCode == 401, let refusal = try? JSONDecoder().decode(Refusal.self, from: data) {
            throw LauncherError.xboxSignInRefused(code: refusal.code)
        }
        try ServiceResponse.requireSuccess(response)
        return try Self.token(from: data)
    }

    private static func token(from data: Data) throws -> XboxToken {
        let body = try ServiceResponse.decode(TokenResponse.self, from: data, service: serviceName)
        guard let userHash = body.displayClaims.users.first?.userHash else {
            throw LauncherError.unexpectedResponse(service: serviceName, reason: "no user hash")
        }
        return XboxToken(token: body.token, userHash: userHash)
    }
}

nonisolated private struct TokenResponse: Decodable {
    struct DisplayClaims: Decodable {
        struct User: Decodable {
            let userHash: String

            private enum CodingKeys: String, CodingKey {
                case userHash = "uhs"
            }
        }

        let users: [User]

        private enum CodingKeys: String, CodingKey {
            case users = "xui"
        }
    }

    let token: String
    let displayClaims: DisplayClaims

    private enum CodingKeys: String, CodingKey {
        case token = "Token"
        case displayClaims = "DisplayClaims"
    }
}

nonisolated private struct Refusal: Decodable {
    let code: Int

    private enum CodingKeys: String, CodingKey {
        case code = "XErr"
    }
}
