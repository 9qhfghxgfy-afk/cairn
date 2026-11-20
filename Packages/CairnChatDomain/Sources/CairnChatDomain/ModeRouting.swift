import Foundation

/// What sort of engine an id names, for the purpose of routing a chat's mode.
///
/// `NetworkClass` alone cannot say this. A stand-in engine and a real on-device model both report
/// `.onDevice`, and both really do send nothing anywhere — but switching a chat to "On device"
/// means putting it on a model that exists, not on the stub a fresh install carries. So the kind
/// is declared by the engine, and the network class keeps being the privacy fact it always was.
public enum EngineKind: String, Sendable, Equatable, CaseIterable {
    /// Runs a model on this device — Apple's system model, or weights this app downloaded.
    case localModel
    /// Answers from a server this app connects to, private or public.
    case server
    /// A stand-in for tests and for a fresh install: it answers, and runs no model.
    case standIn
}

/// Which engine a mode has to be answered by.
///
/// A mode is a routing decision, so the choice of engine belongs beside it. Before this rule
/// existed, switching a chat to "On device" changed the label and nothing else: a plain turn went
/// on answering from whatever server the session was already pointed at, which is a switch that
/// reports a mode it does not honour.
///
/// Pure, and it returns nil rather than guessing. An engine that is not configured is not created
/// by this rule — the user is told what is missing elsewhere, in `HybridPlan`'s refusal for the
/// hybrid modes and in the Servers screen's empty state for a remote one.
public enum ModeRouting {
    /// The engine this mode must use, or nil to leave the session where it is.
    ///
    /// - Parameters:
    ///   - engines: every engine id the app has registered, in the order it lists them.
    ///   - kinds: what each of those ids is. An id missing from the map is treated as a stand-in.
    ///   - current: the engine the session is on now, so a mode that is already honoured causes no
    ///     churn — repointing an engine also reloads its model list.
    ///   - preferredRemote: the engine built from the server the app has chosen, when there is one.
    public static func engineID(
        for mode: InferenceMode,
        engines: [String],
        kinds: [String: EngineKind],
        current: String?,
        preferredRemote: String? = nil
    ) -> String? {
        // A hybrid turn names its engines in its own plan and asks both, so its mode never
        // repoints the session — the session's engine is only the one the panels' side labels use.
        guard let wanted = requiredKind(for: mode) else { return nil }
        guard kinds[current ?? ""] != wanted else { return nil }
        if wanted == .server,
           let preferredRemote,
           engines.contains(preferredRemote),
           kinds[preferredRemote] == .server {
            return preferredRemote
        }
        return engines.first { kinds[$0] == wanted }
    }

    /// The kind a mode insists on, or nil when the mode runs more than one engine and so insists on
    /// none of them alone.
    public static func requiredKind(for mode: InferenceMode) -> EngineKind? {
        switch mode {
        case .onDeviceOnly: return .localModel
        case .remoteOnly: return .server
        case .hybridParallel, .hybridSynthesized: return nil
        }
    }
}
