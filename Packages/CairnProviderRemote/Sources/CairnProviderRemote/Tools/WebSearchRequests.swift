import Foundation
import CairnChatDomain

/// The two rules every provider applies to a request before it is built: is this address one Cairn may
/// use, and does this request get the credential it needs.
///
/// Both live in one place so a new provider cannot quietly invent a third answer. The address rule is the
/// app-wide transport rule restated for a search row — https to a public host, plain http only to a
/// private one — and the credential rule is the reason `hasCredential` is stored separately from the
/// secret: a row that says it authenticates but has nothing in the Keychain is a broken row, and that is a
/// named failure before a byte leaves, not a `401` after.
enum WebSearchRequests {
    /// nil when the address is usable; otherwise the specific reason it is not.
    static func failureForUnusable(_ url: URL?) -> WebSearchFailure? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty
        else { return .invalidEndpoint }
        guard scheme == "https" || scheme == "http" else { return .invalidEndpoint }
        // Credentials in an address are refused, not stripped: a token in a URL ends up in somebody's
        // access log, and the credential field is the place that keeps it out of the settings store.
        guard url.user == nil, url.password == nil else { return .invalidEndpoint }
        if scheme == "http", NetworkClassRouting.classify(host: host) == .publicInternet {
            return .httpsRequired
        }
        return nil
    }

    /// Puts the credential on the request in the shape the row says it uses.
    ///
    /// Ordinary, non-secret header rows are applied here too, and only here — they were validated as
    /// credential-free when the row was saved, which is what makes it safe to write them into a request.
    static func apply(
        credential: String?,
        to request: inout URLRequest,
        profile: WebSearchProviderProfile
    ) -> WebSearchFailure? {
        // The row's own timeout, so a slow instance is a named timeout rather than the transport default.
        request.timeoutInterval = TimeInterval(
            min(max(profile.timeoutSeconds, 1), WebSearchProviderProfile.timeoutRange.upperBound)
        )
        for (name, value) in profile.customHeaders where !name.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }
        guard let shape = profile.credentialShape else { return nil }
        let secret = credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !secret.isEmpty else { return .providerUnavailable }
        switch shape {
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .secretHeader(let name):
            request.setValue(secret, forHTTPHeaderField: name)
        }
        return nil
    }
}
