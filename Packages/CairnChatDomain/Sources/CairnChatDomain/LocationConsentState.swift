import Foundation

/// What has been decided about reading this device's position.
///
/// Three states, because there are three real situations and collapsing them is how a consent prompt
/// becomes a formality. `undecided` means nobody has been asked; `granted` and `denied` are both answers,
/// and a denied answer is not a prompt to be worn down by asking again next turn.
public enum LocationConsentState: String, Sendable, Equatable, Codable, CaseIterable {
    case undecided
    case granted
    case denied

    public var allowsLocation: Bool { self == .granted }

    /// True once a person has answered, so nothing needs to be asked again.
    public var isSettled: Bool { self != .undecided }
}

/// What the state machine says to do next.
///
/// Kept as a value rather than as a `Bool` so "we may proceed" and "we asked and were refused" cannot be
/// confused at the call site, and so a test can read the decision without running the tool.
public enum LocationConsentAction: Sendable, Equatable {
    /// The record already says yes: go straight to a position, and do not interrupt anybody.
    case proceed
    /// Nothing is on the record and there is somebody to ask: put the sheet up, once.
    case askOnce
    /// Refused, or nobody is there to ask. No hardware, and no sheet.
    case refuse(LocationFailureReason)
}

/// The whole consent decision, in one pure function.
///
/// This is the rule `get_location` runs through, written down where it can be tested without a device:
/// an undecided chat asks exactly once, a denied chat never asks again, and **an undecided chat with
/// nobody to ask is a refusal rather than a free pass.** Silence is not permission.
public enum LocationConsentPolicy {
    public static func action(state: LocationConsentState, canAsk: Bool) -> LocationConsentAction {
        switch state {
        case .granted: return .proceed
        case .denied: return .refuse(.permissionDenied)
        case .undecided: return canAsk ? .askOnce : .refuse(.permissionDenied)
        }
    }

    /// The answer a sheet gives, expressed as the state it leaves behind.
    public static func state(after answer: Bool) -> LocationConsentState {
        answer ? .granted : .denied
    }
}
