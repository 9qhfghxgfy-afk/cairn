import Foundation

/// Every way a web search can fail, named.
///
/// The case that matters most is `unrecognizedResponse`, and the reason it exists is the failure it
/// replaces. Before it, a provider whose markup or JSON shape moved answered with an empty list, which the
/// tool reported as "no results" — a model then told the user nothing existed, and nobody learned that the
/// search had actually broken. A change in the provider is now a named failure, and an empty result list is
/// only ever an empty result list.
///
/// Each case carries two strings because there are two readers: `userText` for the card, and `modelReason`
/// for the model. Nothing here carries a URL, a response body, or provider text — a failure message is the
/// one place a page's contents could otherwise leak into a log.
public enum WebSearchFailure: String, Sendable, Equatable, Codable, CaseIterable {
    /// The provider refused the request: `403`, a bot challenge, or a CAPTCHA.
    case blocked
    /// `429`, or a page that says slow down.
    case rateLimited
    /// A response understood as a document, with no readable results structure in it.
    case unrecognizedResponse
    /// A JSON body that did not decode at all.
    case decodeFailed
    /// SearXNG answered, and reported every upstream engine unresponsive.
    case enginesUnavailable
    /// The endpoint is on the public internet and was addressed over http.
    case httpsRequired
    /// The stored address is not usable, or is not the address this kind of provider may use.
    case invalidEndpoint
    /// Nothing answered: DNS failure, connection refused, or a tunnel that is down.
    case unreachable
    /// The provider did not answer inside the row's own timeout.
    case timedOut
    /// iOS withheld the local network permission the request needed.
    case localNetworkDenied
    /// The user declined to let this provider receive queries. No request was made.
    case permissionDenied
    /// The active row exists but cannot be used as configured — no credential, or nothing behind it.
    case providerUnavailable

    /// The card's line: what happened, not what to do about it. The fix lives in Settings, and a tool card
    /// is too small to walk anyone there — the card shows a route instead.
    public var userText: String {
        switch self {
        case .blocked: return "The search provider refused the request."
        case .rateLimited: return "The search provider is slowing requests down."
        case .unrecognizedResponse: return "The search provider answered in a form Cairn could not read."
        case .decodeFailed: return "The search provider's answer could not be read."
        case .enginesUnavailable: return "Your instance reported no working upstream engines."
        case .httpsRequired: return "That search address needs a secure connection."
        case .invalidEndpoint: return "The search address is not usable."
        case .unreachable: return "Cairn could not reach the search provider."
        case .timedOut: return "The search provider took too long."
        case .localNetworkDenied: return "iOS did not allow local network access."
        case .permissionDenied: return "You chose not to send queries to this provider."
        case .providerUnavailable: return "The selected search provider is not usable as configured."
        }
    }
}
