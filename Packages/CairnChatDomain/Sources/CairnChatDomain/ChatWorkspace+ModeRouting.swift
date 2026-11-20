import Foundation

/// Putting a chat on the engine its mode names.
///
/// A mode has always been stored, shown in the switcher, and used by the hybrid planner — and a
/// plain turn never consulted it, so "On device" on a session pointed at a laptop answered from the
/// laptop. That is the class of failure this app exists to avoid: the control says one thing and the
/// answer comes from somewhere else. So the mode now routes, through `ModeRouting`, which is pure
/// and unit-tested; this file only carries out the decision.
///
/// What it deliberately does not do:
/// - It never invents an engine. Nothing here registers a provider or writes a server profile, so a
///   mode with nothing behind it changes nothing and the existing refusal (`HybridPlan`) or the
///   Servers screen's own empty state is what the user reads.
/// - It never touches the hybrid modes' session engine. A hybrid turn names both engines in its own
///   plan and asks both; the session's engine is only what the panel labels say.
extension ChatWorkspace {
    func routeEngines(for mode: InferenceMode) {
        let ids = providerIDs
        var kinds: [String: EngineKind] = [:]
        for id in ids { kinds[id] = engine(id: id)?.engineKind ?? .standIn }
        let chosen = ModeRouting.engineID(
            for: mode,
            engines: ids,
            kinds: kinds,
            current: session?.selectedProviderID,
            preferredRemote: preferredRemoteEngineID
        )
        guard let chosen, let session else { return }
        // Same path a hand-tap on the model menu takes, so the model list, the outbound badge and
        // the saved per-server model all behave exactly as they do when the person taps.
        if let profileID = RemoteEngineID.parse(chosen) {
            session.select(serverProfileID: profileID)
        } else {
            session.select(providerID: chosen)
        }
    }

    /// The engine built from the server the app has chosen, when there is one. The active profile is
    /// used rather than the first server in the list: a person who picked a second server and then
    /// chose "Remote server" in the chat means that second server.
    private var preferredRemoteEngineID: String? {
        guard let profileID = selection?.activeProfileID else { return nil }
        return RemoteEngineID.make(profileID: profileID)
    }
}
