import Foundation

/// Where a position comes from, declared here so the domain never names CoreLocation.
///
/// `@MainActor` for the same reason `MailDraftPresenting` is: the thing that produces a fix is a
/// `CLLocationManager`, which has to be created on a thread with a run loop and delivers every callback
/// on the main one. The implementation lives in the app target; this module only ever sees a protocol, a
/// `LocationFix`, and a thrown `LocationFailureReason`.
///
/// One shot, by construction: there is no "start updating" here. A tool that asks for one position and a
/// source that can only give one position is what makes "Cairn does not track you" true in code rather
/// than in a policy.
@MainActor
public protocol LocationFixProviding: Sendable {
    /// One position, now. Throws `LocationFailureReason` for a named refusal; anything else the tool
    /// reports as unavailable. Never returns a partially-measured fix as success.
    func currentFix() async throws -> LocationFix
}

/// The one question `get_location` may not answer for the user: may this app read where you are?
///
/// A closure rather than a protocol so the App layer can close it over its own sheet, exactly as
/// `WebSearchConsentRequester` does, and so a build with no sheet to show passes nil — which the consent
/// gate reads as a refusal, not as permission.
public typealias LocationConsentRequester = @MainActor @Sendable () async -> Bool

/// A source for a build with no position hardware reachable: reports unavailable, and keeps the last
/// question it was asked so a preview or a test can see that it was reached at all.
@MainActor
public final class NoLocationSource: LocationFixProviding {
    public private(set) var wasAsked = false
    public init() {}

    public func currentFix() async throws -> LocationFix {
        wasAsked = true
        throw LocationFailureReason.unavailable
    }
}
