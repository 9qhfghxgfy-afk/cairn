import Foundation
import Observation
import CairnChatDomain

/// View model behind the Download tab: one curated library with two destinations.
///
/// This is a second view model rather than more properties on `ModelManagerModel` on purpose. That one
/// is about a single server's memory and is empty until a profile is chosen; folding the phone's own
/// library into it would make an on-device download depend on a server being selected, which is exactly
/// the mistake the old Download tab made — it asked for a server name to type because that was the only
/// path it had.
///
/// Nothing here opens a connection. The phone path goes through `LocalModelLibraryServicing` and the
/// server path through `ModelManagerModel`, both injected; this type decides what may start, what it
/// reports back, and what a card is allowed to claim.
@Observable @MainActor
public final class ModelCatalogModel {
    public private(set) var rows: [LocalCatalogRow] = []
    public private(set) var destination: ModelCatalogOrigin = .onDevice
    public private(set) var isLoading = false
    /// The card the sheet is open on. Settable so `.sheet(item:)` can close it, and closing it does not
    /// touch the transfer — a person who sends a model to a server and swipes the sheet away meant the
    /// download, not the sheet.
    public var focused: LocalCatalogRow?
    public var notice: String?
    public var filter = ModelCatalogFilter()

    let library: (any LocalModelLibraryServicing)?
    let servers: ModelManagerModel?
    let traffic: ModelTrafficSwitch
    /// The Ollama servers this person has configured, read through on demand. A server added in
    /// Settings has to be offerable here without relaunching the app, and copying the list at launch is
    /// how a screen ends up offering a server that was deleted an hour ago.
    let ollamaTargets: @MainActor () -> [ServerProfile]
    /// The Ollama server chosen inside the detail sheet for a pull the open server cannot run. Held so
    /// the sheet can show which server a tag would actually be sent to, rather than leaving it implied.
    /// `internal(set)`: the sourcing half in another file moves it, and nothing outside this module may.
    public internal(set) var pullTarget: ServerProfile?
    /// True once the person has moved the source switch themselves. Until then the screen is allowed to
    /// pick a source from the server that opened Models; after that it must not second-guess them.
    public private(set) var sourceChosen = false
    // `internal`, not `private`: the transfer half of this type lives in
    // `ModelCatalogModel+Transfers.swift`, and a `private` member is unreachable from an extension in
    // another file. Nothing outside this module can see them either way.
    var task: Task<Void, Never>?
    var pulledID: String?
    var phoneStatus: ModelTransferStatus?

    public init(
        library: (any LocalModelLibraryServicing)?,
        servers: ModelManagerModel?,
        traffic: ModelTrafficSwitch = .memory(),
        ollamaTargets: @escaping @MainActor () -> [ServerProfile] = { [] }
    ) {
        self.library = library
        self.servers = servers
        self.traffic = traffic
        self.ollamaTargets = ollamaTargets
    }

    /// Whether the phone path can actually run. False means the App layer handed over no library — no
    /// storage, or no wiring on this build — which is a fact to state, not a button to disable silently.
    public var offersPhone: Bool { library != nil }
    public var offersServer: Bool {
        guard let servers, servers.profile != nil else { return false }
        return servers.offersLifecycle
    }

    public var isDownloading: Bool { task != nil || serverPullIsInFlight }

    /// Called when a transfer stops, so the App layer can re-read what the phone now holds.
    ///
    /// The on-device engine report is the App layer's to compute — this module can see neither a
    /// filesystem nor a runtime — and without this hook the Servers screen would go on saying "no model
    /// installed" about a model that finished downloading a minute ago, until the app was relaunched.
    public var onTransferSettled: (@MainActor () -> Void)?

    /// Repositories this phone is holding bytes for, with nothing running.
    ///
    /// A pause and an interruption are both invisible once a transfer leaves the view model: the row would
    /// then offer a fresh-looking Download button for four gigabytes already sitting on the device, and
    /// progress nobody mentions is how a person ends up deleting a model and re-fetching what they had. This
    /// set is what makes a row say "1.2 GB of 4.1 GB kept — Resume" instead of pretending to be untouched.
    public private(set) var partialRows: Set<String> = []

    /// Which rows are holding kept bytes, read from the store rather than remembered in memory.
    ///
    /// The store is asked because it is the thing that survives: a download iOS killed with no Pause button
    /// pressed is exactly the case this is for, and nothing in memory would still be there to remember it.
    /// Rows with something in flight are skipped — asking about those races the transfer that is writing the
    /// very blocks this question is about.
    public func refreshPartials() async {
        guard let library else {
            partialRows = []
            return
        }
        var found: Set<String> = []
        for row in rows where !row.isInstalled {
            if transfers[row.id] != nil { continue }
            if let status = phoneStatus, status.entryID == row.id, status.isInFlight { continue }
            if await library.keepsPartialTransfer(repoID: row.repoID) {
                found.insert(row.id)
            }
        }
        partialRows = found
    }

    /// The cards to draw, in the chosen order, with a typed name offered as its own card when the
    /// library does not carry it.
    public var visibleRows: [LocalCatalogRow] {
        ModelCatalogQuery.rows(rows, filter: filter, origin: destination)
    }

    public func choose(_ destination: ModelCatalogOrigin) async {
        // Moving the switch by hand is a decision, and it outranks whatever the opening server implies
        // from then on — otherwise every visit to Models would move the switch back.
        sourceChosen = true
        guard self.destination != destination else { return }
        self.destination = destination
        await refresh()
    }

    /// Re-reads the list for the destination in front of the user.
    ///
    /// The phone's list comes from the service, which is the only thing that can see what is on disk. The
    /// server's list is the curated Ollama tags marked against the names that server reported — the
    /// library a server holds is its own, and inventing a list for it would be a guess about someone
    /// else's machine.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        // Captured before the await. Two refreshes can overlap — the screen's task and a source switch —
        // and a slow answer from the store must not drop the list of a source the user has already left.
        let wanted = destination
        if wanted.landsOnThisPhone {
            rows = ModelCatalog.onDevice
            guard let library else { return }
            do {
                let read = try await library.catalogRows()
                guard destination == wanted else { return }
                rows = read
            } catch {
                guard destination == wanted else { return }
                // The curated list stays on screen with its installed marks missing rather than
                // emptying the tab: "no models" would be a claim nobody checked.
                notice = error.localizedDescription
            }
            // A refresh answers three questions, not one: what is installed, what is running, and what is
            // being kept. The third is the one a person loses sleep over, and it is the only one that cannot
            // be inferred from the other two.
            await refreshPartials()
        } else {
            let held = Set(servers?.installed.map(\.id) ?? [])
            rows = ModelCatalog.ollama.map { $0.marking(installed: held.contains($0.repoID)) }
        }
    }

    /// Starts one transfer. The destination decides the path, and the acknowledgement decides whether
    /// the phone path may start at all.
    public func download(_ row: LocalCatalogRow) {
        guard !isDownloading else { return }
        notice = nil
        focused = row
        if row.origin.landsOnThisPhone {
            startPhoneDownload(row)
        } else {
            startServerPull(row)
        }
    }

    /// A card's transfer state lives with the transfers that produce it, in
    /// `ModelCatalogModel+Transfers.swift`.

    public func cancel() {
        if let task {
            task.cancel()
            self.task = nil
            if let status = phoneStatus {
                phoneStatus = ModelTransferStatus(entryID: status.entryID, state: .stopped)
            }
        }
        if pulledID != nil {
            servers?.stopPull()
            pulledID = nil
        }
    }

    /// Applies a source change for the sourcing half in `ModelCatalogModel+Sourcing.swift`. The
    /// `destination` setter is `private(set)`, so only this file can move it; a public setter would let
    /// any view claim a source without refreshing the list that goes with it.
    func apply(source: ModelCatalogOrigin) { destination = source }

}
