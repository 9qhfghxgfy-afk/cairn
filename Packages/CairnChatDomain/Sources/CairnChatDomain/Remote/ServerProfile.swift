import Foundation


/// A remote inference server the user configured. Everything about where
/// traffic goes lives here so the privacy rules (network class, opt-in,
/// HTTPS-only) are one validated value, not scattered checks.
///
/// The bearer token is NOT part of this struct: it lives in the Keychain
/// (`.afterFirstUnlockThisDeviceOnly`) under this profile's id. `hasBearerToken`
/// is display state only. Custom header values are non-secret by policy —
/// Authorization belongs in the token field, enforced by validation.
public struct ServerProfile: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var kind: ServerProfileKind
    /// Canonical `scheme://host[:port]` with no trailing slash, path, or query.
    public var baseURLString: String
    public var customHeaders: [String: String]
    public var hasBearerToken: Bool
    public var enabled: Bool
    /// Explicit user consent for `.publicInternet` servers, captured at save time.
    public var publicInternetOptIn: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ServerProfileKind,
        baseURLString: String,
        customHeaders: [String: String] = [:],
        hasBearerToken: Bool = false,
        enabled: Bool = true,
        publicInternetOptIn: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURLString = baseURLString
        self.customHeaders = customHeaders
        self.hasBearerToken = hasBearerToken
        self.enabled = enabled
        self.publicInternetOptIn = publicInternetOptIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var networkClass: NetworkClass {
        NetworkClassRouting.classify(fromURLString: baseURLString)
    }

    public var isPlaintext: Bool { baseURLString.hasPrefix("http://") }

    /// A `.publicInternet` profile may not be registered until the user opted in.
    public var usableNow: Bool {
        enabled && (!networkClass.requiresOptIn || publicInternetOptIn)
    }

    /// Hosts that may use plaintext http (dev/test only; ATS exempts loopback).
    public static let loopbackHosts: Set<String> = [
        "localhost", "127.0.0.1", "[::1]", "::1",
    ]
}

extension ServerProfile {
    /// Parses and canonicalizes to `scheme://host[:port]`; nil when unusable.
    /// https is required everywhere except loopback hosts.
    public static func canonicalize(urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        guard let rawScheme = components.scheme?.lowercased(), !rawScheme.isEmpty else { return nil }
        guard rawScheme == "https" || rawScheme == "http" else { return nil }
        guard let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        // Plaintext is only tolerated on loopback (dev / CI stub servers).
        if rawScheme == "http" && !loopbackHosts.contains(host) { return nil }
        guard components.user == nil && components.password == nil else { return nil }
        guard components.query == nil && components.fragment == nil else { return nil }
        guard components.path.isEmpty || components.path == "/" else { return nil }

        components.scheme = rawScheme
        components.host = host
        components.path = ""
        return components.string
    }
}
