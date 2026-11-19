import Foundation
import CairnChatDomain

/// Asking a person, once, whether this provider may receive their queries.
///
/// The tool cannot present anything: it runs inside a turn, on a background actor, with no view and no
/// window. So the question is handed out as a closure the app supplies, and the answer comes back as a
/// Bool. Three things are true of every call through this seam, and they are what makes it safe:
///
/// - It is asked **before the request is built**, so a refusal costs no socket, no bytes and no latency.
/// - It is asked **once per provider**. The app records the answer in `WebSearchConsentState` — a grant
///   lets later searches run, a denial makes them fail with the same typed refusal without asking again,
///   so "no" is an answer rather than an annoyance to be worn down.
/// - Nothing here chooses a provider. A refusal stops the search; it never sends the query somewhere else.
///
/// A build with no requester — a preview, a test host, a Mac CLI — gets the typed "Cairn has to ask
/// first" refusal rather than a silent yes, which is the only honest answer when nobody is there to ask.
public typealias WebSearchConsentRequester =
    @MainActor @Sendable (WebSearchProviderProfile) async -> Bool
