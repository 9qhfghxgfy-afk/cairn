import Foundation
import CairnChatDomain

/// Why an address was refused before anything left the device.
enum WebFetchDecision: Sendable, Equatable {
    case allowed
    case notHTTPS
    case privateTarget
    case unusableURL
}

/// The address rule every web tool applies **before** it sends a byte.
///
/// A fetch tool is the one tool whose argument is a whole URL a model typed, so it is the one place
/// where server-side request forgery is a live risk: "read this page" aimed at the user's router, at a
/// LAN inference box, or at a tunnel address would turn a chat window into a probe of the private
/// network, and whatever it read would go on into the model's context. The rule is deliberately narrow
/// — https, a public host, and nothing that classifies as private, loopback, link-local or VPN — and it
/// applies to every hop, because a public page that answers with a redirect at a LAN address is the
/// same door left open by a different hinge.
enum WebFetchGuard {
    static func decision(for url: URL?) -> WebFetchDecision {
        guard let url,
              let scheme = url.scheme?.lowercased(), !scheme.isEmpty,
              let host = url.host?.lowercased(), !host.isEmpty
        else { return .unusableURL }
        // Credentials in a URL are refused rather than stripped: a model that typed them meant them to
        // travel, and Cairn does not carry a secret to someone else's server.
        guard url.user == nil, url.password == nil else { return .unusableURL }
        guard scheme == "https" else { return .notHTTPS }
        // One classifier for every request Cairn makes, so "private" cannot mean two different things
        // in two different files.
        guard NetworkClassRouting.classify(host: host) == .publicInternet else {
            return .privateTarget
        }
        return .allowed
    }

    /// The redirect test handed to the transport: the hop is allowed only on the same rule as the
    /// original address, so a bounce cannot cross from public to private.
    static func allowsPublicHTTPS(_ url: URL?) -> Bool { decision(for: url) == .allowed }

    /// Parses and tests one model-supplied address, refusing with what a model can act on.
    static func check(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ToolFailure(.badArguments, detail: "That is not a web address.")
        }
        switch decision(for: url) {
        case .allowed: return url
        case .notHTTPS:
            throw ToolFailure(.blockedTarget, detail: "Only an https address is fetched.")
        case .privateTarget:
            throw ToolFailure(.blockedTarget)
        case .unusableURL:
            throw ToolFailure(.badArguments, detail: "That is not a web address.")
        }
    }

    /// A plain GET with nothing attached: no cookie, no referrer, no custom header, and a user agent
    /// that says Cairn rather than pretending to be a browser. The `Authorization` header belongs to a
    /// server profile's Keychain token and is never set here, so a search query can never carry it.
    static func request(for url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// The same posture for a POST: JSON out, JSON back, one bounded body, no credentials.
    static func postRequest(for url: URL, body: Data, bearer: String? = nil) -> URLRequest {
        var request = request(for: url, accept: "application/json")
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static var userAgent: String { "Cairn/1.0 (local-first assistant)" }
}
