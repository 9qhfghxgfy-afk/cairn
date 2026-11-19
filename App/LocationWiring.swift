import CairnAppUI
import CairnChatDomain
import Foundation

/// The location surface at the only layer that can hold all three parts of it.
///
/// The record of consent is the domain's (`LocationConsentGate`), the question is the UI's
/// (`LocationConsentModel`, drawn by `LocationConsentSheet`), and the radio is CoreLocation's
/// (`LocationProvider`). None of the three may reach the other two — the domain must not name CoreLocation,
/// and `CairnAppUI` must not import it — so the join happens here, in one file, the same way
/// `WebSearchWiring` joins a sheet to two web tools.
///
/// The consent record is **per app run**, not stored. What is durable is iOS's own authorization, which the
/// system keeps and a person revokes in the Settings app; a second record in Cairn's database could only
/// ever disagree with it. So the question is asked once per run, and the per-chat `Tools` switch decides
/// whether the tool is offered at all. Nothing about a position is written to disk by this type.
@MainActor
final class LocationWiring {
    /// The record `get_location` consults before it reaches for anything.
    let gate: LocationConsentGate
    /// The sheet the gate's question is drawn from, held here so the app can put it on screen.
    let consent = LocationConsentModel()

    private let source: any LocationFixProviding

    private init(gate: LocationConsentGate, source: any LocationFixProviding) {
        self.gate = gate
        self.source = source
    }

    /// Builds the surface.
    ///
    /// - Parameters:
    ///   - gate: the consent record to carry. A registry rebuild passes the gate it already has, because a
    ///     fresh gate would put the sheet back up in front of a person who has already answered — which is
    ///     how a permission prompt becomes noise. The default is the record a first install starts with.
    ///   - source: where a position comes from. The app installs the CoreLocation provider; a test installs
    ///     a counted fake, which is what lets the consent order — refuse means zero source calls — be proved
    ///     here rather than asserted.
    static func install(
        gate: LocationConsentGate = LocationConsentGate(),
        source: any LocationFixProviding = LocationProvider()
    ) -> LocationWiring {
        LocationWiring(gate: gate, source: source)
    }


    /// The seam the gate asks through: may this device say where it is?
    ///
    /// This is the only path that puts the location sheet in front of a person. A wiring object that was
    /// never handed to a root view has a model with no window, and the gate still asks it — the turn then
    /// waits for a sheet nobody can see, which is why the app installs the sheet alongside the tool rather
    /// than optionally.
    var asker: LocationConsentRequester {
        let model = consent
        return { await model.allowLocation() }
    }

    /// The tool, assembled from this wiring's own record, sheet and source. Built per registry rather than
    /// cached: it is a struct of three references, and building it each time is what keeps a rebuilt
    /// registry pointing at the same gate instead of quietly starting a fresh consent record.
    var tool: GetLocationTool {
        GetLocationTool(source: source, consent: gate, asker: asker)
    }
}
