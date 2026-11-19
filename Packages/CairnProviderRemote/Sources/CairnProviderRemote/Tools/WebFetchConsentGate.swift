import Foundation
import CairnChatDomain

/// Asking a person, once, whether a page may be read off this device.
///
/// The same seam `WebSearchConsentGate` declares, for the other web tool. A page read is not a query to a
/// provider the user selected — the address came out of a model's prose — so the question is the same
/// question with a different subject: what leaves, and to which host.
///
/// One record answers both tools, and that is a deliberate choice rather than a shortcut. The decision a
/// person makes is "Cairn may read the web"; asking separately for each tool would mean a sheet that
/// interrupts twice for one decision, which is how people learn to tap the first button without reading.
///
/// Same three guarantees as the search seam: asked **before the request is built**, answered **once**, and a
/// refusal sends nothing at all.
public typealias WebFetchConsentRequester = @MainActor @Sendable (URL) async -> Bool
