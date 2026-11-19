import Foundation

/// Why a position could not be given, as a value rather than as a string.
///
/// Every case is returned to the model as the tool's answer, so each one has to say something a model
/// can act on — and four of them say "no further attempt will help". A location refusal is a permission
/// or a setting a person has to change, and a model that retries it is spending steps on a decision that
/// is not its own. Nothing here is a coordinate, and nothing here carries one.
public enum LocationFailureReason: String, Sendable, Equatable, Codable, CaseIterable, Error {
    /// The user declined Cairn's own sheet, or iOS has this app's location access turned off.
    case permissionDenied
    /// Location Services are off at the system level, so no app can read a position.
    case servicesDisabled
    /// The device was asked and did not answer within the bound.
    case timedOut
    /// This device or this build has no position source at all.
    case unavailable

    /// What the model is told. Written so that the honest next move is to say the answer out loud, not
    /// to guess a place — which is the specific failure a location tool can cause.
    public var userText: String {
        switch self {
        case .permissionDenied:
            return "The user has not allowed Cairn to use their location, so no position was read. "
                + "Say that plainly and answer without naming a place."
        case .servicesDisabled:
            return "Location Services are turned off on this device, so no position can be read. "
                + "The user can turn them on in the iOS Settings app."
        case .timedOut:
            return "The device did not produce a position within the allowed time. A phone indoors or "
                + "with a clear sky may answer on another try; do not state a position meanwhile."
        case .unavailable:
            return "This device cannot provide a location to Cairn at all."
        }
    }

    /// The tool-level name the registry and the card show. `.timedOut` and `.unavailable` already exist
    /// for exactly these meanings, so they are reused rather than duplicated.
    public var toolError: ToolError {
        switch self {
        case .permissionDenied: return .locationDenied
        case .servicesDisabled: return .locationDisabled
        case .timedOut: return .timedOut
        case .unavailable: return .unavailable
        }
    }

    /// Only a fix that never arrived is worth another call. A refusal and a switched-off service are the
    /// user's to change, and `ToolError.modelCanRetry` says the same thing from the other side.
    public var modelCanRetry: Bool { self == .timedOut }
}
