import Foundation

/// What a search failure means to the model, to the tool loop, and to the Settings route.
///
/// The split is deliberate: a card needs one short line, a model needs enough to decide whether to change
/// its query or stop, and the loop needs to know whether another step is worth spending at all. Three
/// questions, three answers, all derived from the same case so they cannot drift.
public extension WebSearchFailure {
    /// The model's half of the result, without the provider's name. `modelText(providerName:)` is what the
    /// loop sends.
    ///
    /// Two cases say outright that a retry is pointless. A rate limit and a refusal will not answer a
    /// better query, and a model that spends two more steps finding that out has spent the user's context
    /// on nothing.
    var modelReason: String {
        switch self {
        case .blocked:
            return "it refused the request, possibly as a matter of policy. Do not retry this query."
        case .rateLimited:
            return "it is rate limiting requests. Do not retry in this turn."
        case .unrecognizedResponse:
            return "its answer did not contain a readable results section, so this is not a report of "
                + "nothing being found."
        case .decodeFailed:
            return "its answer could not be decoded, so this is not a report of nothing being found."
        case .enginesUnavailable:
            return "the instance has no working upstream engines right now."
        case .httpsRequired:
            return "the configured address is not secure, so the request was not sent."
        case .invalidEndpoint:
            return "the configured address is not usable, so the request was not sent."
        case .unreachable:
            return "it could not be reached."
        case .timedOut:
            return "it did not answer in time."
        case .localNetworkDenied:
            return "the device blocked access to the local network, so the request was not sent."
        case .permissionDenied:
            return "the user has not allowed sending queries to this provider. Do not retry; answer "
                + "without searching, or say that you could not search."
        case .providerUnavailable:
            return "the provider the user selected is not configured correctly, so no request was sent."
        }
    }

    /// The tool result the model reads. The provider is named because a failed search through a
    /// self-hosted instance and a failed search through DuckDuckGo are different facts, and the model
    /// should not have to guess which one it is about to report.
    func modelText(providerName: String) -> String {
        "Web search via \(providerName) did not run: \(modelReason)"
    }

    /// The typed tool error the card and the loop carry.
    var toolError: ToolError {
        switch self {
        case .blocked: return .endpointRejected
        case .rateLimited: return .rateLimited
        case .unrecognizedResponse, .decodeFailed: return .endpointMalformed
        case .enginesUnavailable, .providerUnavailable, .invalidEndpoint: return .providerUnavailable
        case .httpsRequired: return .httpsRequired
        case .unreachable: return .endpointUnreachable
        case .timedOut: return .timedOut
        case .localNetworkDenied: return .localNetworkDenied
        case .permissionDenied: return .internetNotAllowed
        }
    }

    /// True when the fix is a setting the user has to change, not a different query. The card offers a
    /// route to Settings on this condition and no other, so a broken address does not turn into a model
    /// that keeps rewriting its search.
    var isConfigurationProblem: Bool {
        switch self {
        case .httpsRequired, .invalidEndpoint, .providerUnavailable, .localNetworkDenied,
             .permissionDenied:
            return true
        case .blocked, .rateLimited, .unrecognizedResponse, .decodeFailed, .enginesUnavailable,
             .unreachable, .timedOut:
            return false
        }
    }
}
