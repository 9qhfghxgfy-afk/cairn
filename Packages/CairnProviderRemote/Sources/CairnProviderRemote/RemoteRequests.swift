import Foundation
import CairnChatDomain

/// Builds every request a profile makes: canonical base + path, the Keychain-backed
/// bearer, and the profile's custom headers.
///
/// Credential-bearing headers set in the settings store are dropped here as defence in
/// depth (validation already rejects `Authorization`): tokens reach the network only
/// through the token field, which is Keychain-backed. Nothing logs a URL or a header.
enum RemoteRequests {
    /// Headers that must never come from the plain settings store.
    static let reservedHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "api-key", "host", "content-length", "transfer-encoding", "connection",
    ]

    static func url(base: String, path: String) -> URL? {
        guard var components = URLComponents(string: base), components.host != nil else { return nil }
        components.path = path
        return components.url
    }

    static func make(
        profile: ServerProfile,
        method: String,
        path: String,
        body: Data? = nil,
        accept: String,
        bearer: String? = nil
    ) -> URLRequest? {
        guard let target = url(base: profile.baseURLString, path: path) else { return nil }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in profile.customHeaders {
            let header = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !header.isEmpty, !reservedHeaders.contains(header.lowercased()) else { continue }
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
