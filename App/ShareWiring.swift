import CairnAppUI
import CairnChatDomain
import CairnProviderRemote
import SwiftUI

/// P4 wiring: one LAN share surface, built once, alive only while Cairn is on screen.
///
/// This is the layer that has to own it, for two reasons no other layer can talk its way out of.
/// The surface needs three things at once — the app's **live engine list**, the **Keychain** that holds
/// the inbound key, and a **listener** — and `CairnAppUI` may hold none of them (it imports neither
/// `Network` nor `Security`) while `CairnChatDomain` may not hold any of them. And the rule that keeps
/// this feature honest is a scene rule: iOS suspends the app minutes after it leaves the foreground, so
/// only a layer that is *told* about the phase change can close the port. A screen cannot promise that;
/// a screen can be closed while the socket it opened keeps answering.
@MainActor
final class ShareWiring {
    let model: ShareModel
    private let server: CairnShareServer

    private init(server: CairnShareServer, model: ShareModel) {
        self.server = server
        self.model = model
    }

    /// Builds the surface over the app's live engine list and hangs its screen on the Servers model.
    ///
    /// The engine list is read **when sharing starts**, not snapshotted here, which is the
    /// `.running(local:)` handoff the milestone asks for: whatever this process can actually run at that
    /// moment — the Apple on-device model, an MLX model that has been loaded, and every enabled server
    /// profile the registry holds — becomes the `ShareEngineTable` a turn is dispatched against, filtered
    /// to the engines the user ticked. A table frozen at launch would offer a model whose server was
    /// deleted an hour ago, and `ShareTurnPump` would then be streaming a failure at a laptop that did
    /// nothing wrong.
    static func install(
        on servers: ServersModel,
        registry: ProviderRegistry,
        tokens: ShareTokenHolding
    ) -> ShareWiring {
        let server = CairnShareServer(engines: { registry.providers })
        let model = ShareModel(serving: server, listing: server, tokens: tokens)
        servers.share = model
        return ShareWiring(server: server, model: model)
    }

    /// The served set a start would build, spelled out as a function so the handoff from the registry to
    /// the share table is something a test can call rather than a side effect of pressing a switch.
    static func servedTable(from registry: ProviderRegistry, selected: [String]) -> ShareEngineTable {
        ShareEngineTable.build(from: registry.providers, selected: selected)
    }

    /// The foreground rule, stated as a function so it can be tested without a scene.
    ///
    /// `.active` only — not `.inactive`. During `.inactive` the app is on screen but not in charge (a
    /// control-centre pull, a notification, the app switcher), and a phone that goes quiet for a second
    /// should not have to re-open a port afterwards. It is the same rule either way: the port lives while
    /// the person using the phone can see that it lives.
    static func allowsListening(_ phase: ScenePhase) -> Bool { phase == .active }

    /// Scene-phase hook. Leaving the foreground closes the port and turns the switch off, because a
    /// suspended app with a port still open is a reachable phone with nothing on screen saying so — and
    /// because a switch left glowing over a dead port teaches the user not to trust it.
    func handlePhase(_ phase: ScenePhase) async {
        guard !ShareWiring.allowsListening(phase) else { return }
        await model.releaseToBackground()
    }

    /// Stops the surface when the app is torn down. Not strictly needed on iOS — the process is killed
    /// with the listener inside it — but a surface with no owner should close itself rather than rely on
    /// being collected.
    func shutdown() async {
        await server.stop()
    }
}
