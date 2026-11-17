import Foundation

/// What a server row's status dot may honestly claim. Derived, never stored: a dot that remembered
/// yesterday's answer would be a lie the moment the box went to sleep.
public enum ServerConnectionStatus: Sendable, Equatable {
    /// Never tested in this run.
    case unchecked
    /// A test is in flight.
    case checking
    /// A test answered: models and latency came back from the server itself.
    case online(modelCount: Int, latencyMilliseconds: Int)
    /// Cannot be reached at all: disabled, or a public server with no outbound opt-in.
    case inert
    /// A test was tried and failed; the outcome's own hint explains which half.
    case failed(message: String)

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    public var shortLabel: String {
        switch self {
        case .unchecked: return "Not tested"
        case .checking: return "Checking"
        case .online: return "Connected"
        case .inert: return "Inert"
        case .failed: return "No answer"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .unchecked: return "Connection not tested yet"
        case .checking: return "Testing this server now"
        case .online(let count, let latency):
            return "Connected — \(count) model\(count == 1 ? "" : "s"), \(latency) milliseconds"
        case .inert: return "This server cannot be reached until it is turned on"
        case .failed(let message): return "Not connected: \(message)"
        }
    }

    /// The rule the dot reads. Order matters: a test in flight outranks everything, and a server
    /// that cannot be reached outranks a stale success, so a disabled row never looks live.
    public static func derive(
        profile: ServerProfile,
        outcome: RemoteTestOutcome?,
        isTesting: Bool
    ) -> ServerConnectionStatus {
        if isTesting { return .checking }
        guard profile.usableNow else { return .inert }
        guard let outcome else { return .unchecked }
        if case .connected(_, let count, let latency) = outcome {
            return .online(modelCount: count, latencyMilliseconds: latency)
        }
        return .failed(message: outcome.userMessage)
    }
}
