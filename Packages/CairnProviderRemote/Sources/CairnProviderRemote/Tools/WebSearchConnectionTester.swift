import Foundation
import CairnChatDomain

/// What "Test Connection" answered.
///
/// The same taxonomy the tool reports during a turn, on purpose: a row that tests `blocked` must report
/// `blocked` in a conversation. Two names for one condition is how a settings screen ends up disagreeing
/// with a tool card, and then the user has to work out which one is lying.
public enum WebSearchTestStatus: Sendable, Equatable {
    case ok(results: Int, milliseconds: Int)
    case empty
    case failure(WebSearchFailure)

    /// The line under the row. `format=json` is named only for SearXNG, because that is the one case where
    /// the instance is fine and its configuration is the thing in the way — and it is by far the most common
    /// reason a first test comes back `403` or unreadable.
    public func detail(providerKind: WebSearchProviderKind) -> String {
        switch self {
        case .ok(let count, let milliseconds):
            return "Reachable — \(count) result\(count == 1 ? "" : "s") in \(milliseconds) ms."
        case .empty:
            return "Reachable, but it returned nothing for the test query."
        case .failure(let failure):
            if failure == .unrecognizedResponse, providerKind == .searxng {
                return "It answered, but not as JSON. A SearXNG instance has to allow format=json in "
                    + "settings.yml before Cairn can read it."
            }
            if failure == .blocked, providerKind == .searxng {
                return "The instance refused the request. The usual reason is that JSON output is not "
                    + "enabled in settings.yml."
            }
            return failure.userText
        }
    }
}

/// One harmless query against one provider row, so a Settings screen can say whether a row works before a
/// conversation has to find out the hard way.
///
/// Deliberately narrow: one fixed query, the row's own parameters, the row's own credential, nothing from
/// any chat. A tester that searched the user's last message would be a privacy hole dressed as a button.
public struct WebSearchConnectionTester: Sendable {
    /// Fixed and boring. A test query should not become somebody's analytics signal.
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
