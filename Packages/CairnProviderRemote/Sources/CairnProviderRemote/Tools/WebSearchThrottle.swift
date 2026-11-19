import Foundation
import CairnChatDomain

/// Pacing and memory-only de-duplication in front of a provider, held for the life of the app.
///
/// The domain type (`WebSearchCourtesy`) is a pure value with a clock handed in; this is the one place that
/// owns the clock and the serialisation, because two searches started in the same second by a tool loop
/// need to become two requests a second apart, and a value type cannot promise that. An actor can, and it
/// needs no lock.
///
/// Two reasons, both real. DuckDuckGo's HTML endpoint is shared, and a model that fires five searches in
/// two seconds is one bad turn away from the endpoint refusing every Cairn user. A SearXNG instance is
/// usually a small box — often the same box as the model server — and hammering it takes down the thing
/// generating the answer.
actor WebSearchThrottle {
    private var courtesy: WebSearchCourtesy

    init(courtesy: WebSearchCourtesy = .default) {
        self.courtesy = courtesy
    }

    /// Results for this exact query and provider, if a recent search already produced them.
    func cachedResults(for key: String) -> [WebSearchResult]? {
        courtesy.cachedResults(for: key, now: Date())
    }

    func remember(_ results: [WebSearchResult], for key: String) {
        courtesy.remember(results, for: key, at: Date())
    }

    /// Waits out the courtesy gap and marks this request as the one the next gap is measured from.
    ///
    /// Returns false when the turn was cancelled while waiting, so a cancelled generation does not go out
    /// to the network after the user has already stopped it — the one case where waiting politely would
    /// mean doing the thing the user just asked not to do.
    @discardableResult
    func beginRequest() async -> Bool {
        let wait = courtesy.delayBefore(Date())
        if wait > 0 {
            let nanoseconds = UInt64(max(0, wait) * 1_000_000_000)
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return false }
        }
        if Task.isCancelled { return false }
        courtesy.noteRequest(at: Date())
        return true
    }

    /// Forgets the cache and the pacing. Called when the active provider changes, because a cached answer
    /// from one provider must never be served as another provider's result.
    func reset() { courtesy.reset() }
}
