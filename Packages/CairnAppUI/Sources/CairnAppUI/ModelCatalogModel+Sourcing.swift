import Foundation
import CairnChatDomain

/// The source half of the Download tab: which library is in front of the user, and which server a tag
/// is actually sent to.
///
/// Split out because these are the two questions the screen gets wrong most easily. A tab that opens
/// empty because it inherited the wrong source reads as a broken app, and a pull started against a
/// server that has no `/api/pull` reads as a broken server. Both answers come from the domain
/// (`ModelCatalogOpening`), so the rule is stated once and the view only draws it.
extension ModelCatalogModel {
    /// The kind of the server Models was opened from, or nil when On-Device opened it.
    public var serverKind: ServerProfileKind? { servers?.profile?.kind }

    /// The word on the switcher, for the header and for the sheet's destination line.
    public var sourceLabel: String { destination.sourceLabel }
    public var sourceBlurb: String { destination.sourceBlurb }

    /// True when the server behind the tab can run a pull for an Ollama tag.
    public var pullsDirectly: Bool { ModelCatalogOpening.pullsDirectly(fromKind: serverKind) }

    /// True when the tab is on the Ollama library and the open server cannot take a pull — the one
    /// state in which the sheet has to name a server rather than assume it.
    public var needsAnotherServer: Bool {
        destination == .ollamaLibrary && !pullsDirectly
    }

    /// The configured Ollama servers a tag could be pulled onto.
    public var ollamaChoices: [ServerProfile] { ollamaTargets() }

    /// The server a pull would go to right now: the one chosen in the sheet, else the open one.
    public var pullDestination: ServerProfile? { pullTarget ?? servers?.profile }

    /// Names the server a tag should be sent to. The sheet shows this before anything starts, so a pull
    /// never arrives at a machine the person did not point it at.
    public func choosePullTarget(_ profile: ServerProfile) {
        pullTarget = profile
    }

    /// Why the Ollama library is showing a server that cannot take a pull, in the screen's words.
    ///
    /// The sentence names the way out rather than only the obstacle: a person who opened Models from LM
    /// Studio is not doing anything wrong, and the fix is one tap away on a different server.
    public var serverGuidance: String {
        let kind = serverKind?.displayName ?? "This server"
        return "\(kind) can list the models it holds but has no install endpoint. Open an Ollama "
            + "server's Models screen to pull a tag, or open a card here and choose which Ollama server "
            + "should take it."
    }

    /// Opens the tab on the source that matches the server that opened Models.
    ///
    /// A hand-moved switch outranks this, which is why `sourceChosen` is checked: a person who chose
    /// Hugging Face once should not find the tab moved because they next opened Models from a server.
    public func openFrom(kind: ServerProfileKind?) async {
        guard !sourceChosen else { await refresh(); return }
        let wanted = ModelCatalogOpening.origin(forKind: kind)
        guard wanted != destination || rows.isEmpty else { return }
        apply(source: wanted)
        await refresh()
    }

    /// Sends one tag to a chosen Ollama server, in place of the server Models was opened from.
    ///
    /// The switch is real: `ModelManagerModel` is repointed at the chosen profile, so the Installed tab
    /// and the progress numbers that follow belong to the server that is actually doing the work.
    public func routePull(to profile: ServerProfile, for row: LocalCatalogRow) async {
        guard let servers else {
            notice = "Choose a server first."
            return
        }
        guard !isDownloading else { return }
        pullTarget = profile
        await servers.open(profile)
        // Re-checked after the await: a tap during the server read can have started a transfer, and a
        // second one started from here would be traffic nobody asked for.
        guard !isDownloading, pullTarget == profile else { return }
        guard servers.offersLifecycle else {
            notice = servers.guidance
            return
        }
        notice = nil
        download(row)
    }
}
