import Foundation
import CairnChatDomain

/// One harmless query against one provider row, so a Settings screen can say whether a row works before a
/// conversation has to find out the hard way.
///
/// The answer it produces, `WebSearchTestStatus`, is a domain value — see that file for why the value and
/// the asking live in different modules. The taxonomy is deliberately the same one the tool reports during
/// a turn: a row that tests `blocked` must report `blocked` in a conversation.
///
/// Deliberately narrow: one fixed query, the row's own parameters, the row's own credential, nothing from
/// any chat. A tester that searched the user's last message would be a privacy hole dressed as a button.
public struct WebSearchConnectionTester: WebSearchConnectionTesting {
    /// Fixed and boring. A test query is Cairn's own words, so it must never become a signal somebody
    /// else counts — a settings button that sends a different query each press is one way a user's
    /// habits leak out of an app that claims otherwise.
    static let testQuery = "hello"

    private let transport: any WebRequesting

    public init(transport: any WebRequesting = WebHTTPTransport()) {
        self.transport = transport
    }

    public func run(
        profile: WebSearchProviderProfile,
        credential: String?,
        resultCount: Int = WebSearchProviderProfile.defaultResultCount
    ) async -> WebSearchTestStatus {
        guard let provider = WebSearchProviderFactory.make(profile: profile) else {
            return .failure(.providerUnavailable)
        }
        let started = Date()
        switch provider.dispatch(for: Self.testQuery, limit: resultCount, credential: credential) {
        case .failure(let failure):
            return .failure(failure)
        case .request(let request, let byteLimit):
            do {
                let response = try await transport.send(
                    request, byteLimit: byteLimit, redirectAllowed: provider.redirectAllowed
                )
                let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
                guard response.succeeded else {
                    return .failure(WebSearchFailure.response(status: response.status))
                }
                switch provider.read(response, limit: resultCount) {
                case .results(let found): return .ok(results: found.count, milliseconds: elapsed)
                case .empty: return .empty
                case .failure(let failure): return .failure(failure)
                }
            } catch {
                if WebSearchTool.isCancellation(error) { return .failure(.timedOut) }
                return .failure(WebSearchFailure.transport(error))
            }
        }
    }
}
