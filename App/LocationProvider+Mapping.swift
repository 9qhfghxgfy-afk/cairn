import CairnChatDomain
import CoreLocation
import Foundation

/// What CoreLocation reports, translated into the four reasons `get_location` is allowed to name.
///
/// Split out of the provider because it is the part worth testing on its own: it is pure, and it is where a
/// wrong translation would do its damage — a denial reported as "no position available" sends a model off
/// to look for a technical fault in a decision that was a person's to make.
extension LocationProvider {
    /// An unrecognised code is `unavailable` rather than a guessed cause, because a confident wrong reason
    /// in a model's context becomes a confident wrong explanation to a person.
    ///
    /// Only the denial has a name worth acting on. iOS reports a globally switched-off Location Service
    /// through the same `CLError.denied` as a per-app refusal, and the remaining `CLError` codes are about
    /// geocoding, heading, and region monitoring — none of which a one-shot `requestLocation()` can produce.
    /// Naming a cause the hardware did not report is worse than naming none.
    ///
    /// `nonisolated` because the delegate runs it on CoreLocation's delivery thread **before** hopping to the
    /// main actor, so that the only thing crossing that boundary is a `Sendable` reason value. Members of an
    /// extension of a `@MainActor` type are main-actor-isolated by default, which would undo that.
    nonisolated static func reason(for error: any Error) -> LocationFailureReason {
        guard (error as? CLError)?.code == .denied else { return .unavailable }
        return .permissionDenied
    }


    /// A fix as the domain's value type, with no place names attached. A `CLPlacemark` costs a network
    /// question to somebody else's geocoder, and that question would make this tool a networked one — which
    /// is the whole thing this tool exists not to be. `nonisolated` for the same reason as `reason(for:)`:
    /// it runs before the hop, so a `CLLocation` never has to be sent anywhere.
    nonisolated static func fix(from location: CLLocation) -> LocationFix {
        LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}
