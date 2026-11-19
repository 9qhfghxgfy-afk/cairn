import Foundation

/// What "Test Connection" answered.
///
/// The same taxonomy the tool reports during a turn, on purpose: a row that tests `blocked` must report
/// `blocked` in a conversation. Two names for one condition is how a settings screen ends up disagreeing
/// with a tool card, and then the user has to work out which one is lying.
///
/// It lives in the domain rather than beside the tester because the *answer* is a pure value while the
/// asking is a socket. A settings screen in `CairnAppUI` has to draw the answer, and that module may not
/// import the module that owns `URLSession` — so the value and the seam are declared here, and only the
/// implementation that opens a connection lives over in `CairnProviderRemote`.
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

/// Asking one provider row one harmless question, behind a seam the settings screen can hold.
///
/// Declared here for the same reason as the status above: `CairnAppUI` draws the result and must not import
/// the module that owns the transport. The App layer injects `WebSearchConnectionTester` from
/// `CairnProviderRemote` into this seam, and the screen never learns which module the answer came from.
///
/// The rule that makes this safe is in the implementation, not here: one fixed query, the row's own
/// parameters, the row's own credential, and nothing from any conversation.
public protocol WebSearchConnectionTesting: Sendable {
    /// - Parameters:
    ///   - profile: the row to test, non-secret by construction.
    ///   - credential: the row's secret read from the Keychain at the moment of the test, or nil.
    ///   - resultCount: the app-wide count, so a test asks the same question a search would.
    func run(
        profile: WebSearchProviderProfile,
        credential: String?,
        resultCount: Int
    ) async -> WebSearchTestStatus
}
