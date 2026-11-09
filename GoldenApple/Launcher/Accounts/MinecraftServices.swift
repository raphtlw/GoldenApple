import Foundation

nonisolated struct MinecraftToken: Sendable {
    let accessToken: String
    let expiresAt: Date
}

nonisolated struct MinecraftProfile: Sendable {
    /// 32 hexadecimal digits without dashes.
    let id: String
    let name: String
    let skinURL: URL?
}

/// Minecraft services: launcher login with an XSTS token, game ownership and the Java profile.
nonisolated struct MinecraftServices: Sendable {
    private static let baseURL = URL(string: "https://api.minecraftservices.com/")!
    private static let serviceName = "Minecraft services"
    private static let ownershipItems: Set<String> = ["product_minecraft", "game_minecraft"]

    let http: HTTPClient

    /// HTTP 403 means Mojang has not approved the Microsoft client ID.
    func login(with xsts: XboxToken) async throws -> MinecraftToken {
        let request = try URLRequest.jsonPost(Self.baseURL.appending(path: "launcher/login"), body: [
            "xtoken": "XBL3.0 x=\(xsts.userHash);\(xsts.token)",
            "platform": "PC_LAUNCHER",
        ])
        let (data, response) = try await http.send(request)
        if response.statusCode == 403 {
            throw LauncherError.clientIDNotApproved
        }
        try ServiceResponse.requireSuccess(response)
        let body = try ServiceResponse.decode(LoginResponse.self, from: data, service: Self.serviceName)
        return MinecraftToken(accessToken: body.accessToken, expiresAt: Date().addingTimeInterval(TimeInterval(body.expiresIn)))
    }

    func ownsMinecraft(accessToken: String) async throws -> Bool {
        var components = URLComponents(url: Self.baseURL.appending(path: "entitlements/license"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "requestId", value: UUID().uuidString.lowercased())]
        let data = try await http.data(for: .bearerGet(components.url!, token: accessToken))
        let body = try ServiceResponse.decode(EntitlementsResponse.self, from: data, service: Self.serviceName)
        return body.items.contains { Self.ownershipItems.contains($0.name) }
    }

    /// HTTP 404 means the account has no Java Edition profile.
    func profile(accessToken: String) async throws -> MinecraftProfile {
        let (data, response) = try await http.send(.bearerGet(Self.baseURL.appending(path: "minecraft/profile"), token: accessToken))
        if response.statusCode == 404 {
            throw LauncherError.noJavaProfile
        }
        try ServiceResponse.requireSuccess(response)
        let body = try ServiceResponse.decode(ProfileResponse.self, from: data, service: Self.serviceName)
        let activeSkin = body.skins?.first { $0.state == "ACTIVE" } ?? body.skins?.first
        return MinecraftProfile(id: body.id.replacing("-", with: "").lowercased(), name: body.name, skinURL: activeSkin.flatMap { URL(string: $0.url) })
    }
}

nonisolated private struct LoginResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

nonisolated private struct EntitlementsResponse: Decodable {
    struct Item: Decodable {
        let name: String
    }

    let items: [Item]
}

nonisolated private struct ProfileResponse: Decodable {
    struct Skin: Decodable {
        let state: String?
        let url: String
    }

    let id: String
    let name: String
    let skins: [Skin]?
}
