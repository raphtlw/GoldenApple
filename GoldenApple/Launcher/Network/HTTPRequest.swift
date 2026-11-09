import Foundation

/// `application/x-www-form-urlencoded` text, also used for query strings.
nonisolated enum FormEncoding {
    private static let unreservedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ fields: KeyValuePairs<String, String>) -> String {
        encode(fields.map { ($0.key, $0.value) })
    }

    static func encode(_ fields: [(String, String)]) -> String {
        fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    /// `url` with the fields as its query string.
    static func url(_ url: URL, query fields: [(String, String)]) -> URL {
        guard !fields.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.percentEncodedQuery = encode(fields)
        return components.url ?? url
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? text
    }
}

nonisolated extension URLRequest {
    /// A POST with a form-encoded body.
    static func formPost(_ url: URL, fields: KeyValuePairs<String, String>) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(FormEncoding.encode(fields).utf8)
        return request
    }

    /// A POST with a JSON object body.
    static func jsonPost(_ url: URL, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// A GET that asks for JSON.
    static func jsonGet(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A GET with `Authorization: Bearer <token>`.
    static func bearerGet(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Decodes JSON answers of web services. A body that does not match is an `unexpectedResponse` error.
nonisolated enum ServiceResponse {
    /// Dates are read as ISO 8601 text.
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        service: String,
        keys: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) throws -> Value {
        let decoder = JSONFiles.makeDecoder()
        decoder.keyDecodingStrategy = keys
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LauncherError.unexpectedResponse(service: service, reason: error.localizedDescription)
        }
    }

    /// Throws `httpStatus` for a status outside 200...299.
    static func requireSuccess(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw LauncherError.httpStatus(url: response.url ?? URL(filePath: "/"), statusCode: response.statusCode)
        }
    }
}
