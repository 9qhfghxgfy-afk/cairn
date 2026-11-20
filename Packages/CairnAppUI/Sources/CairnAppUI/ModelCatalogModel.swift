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
    // `internal`, not `private`: the transfer half of this type lives in
    // `ModelCatalogModel+Transfers.swift`, and a `private` member is unreachable from an extension in
    // another file. Nothing outside this module can see them either way.
    var task: Task<Void, Never>?
    var pulledID: String?
    var phoneStatus: ModelTransferStatus?

    public init(
        library: (any LocalModelLibraryServicing)?,
        servers: ModelManagerModel?,
        traffic: ModelTrafficSwitch = .memory()
    ) {
        self.library = library
        self.servers = servers
        self.traffic = traffic
    }

    public var weightsAreAllowed: Bool { traffic.isGranted() }
    public func allowWeights() { traffic.setGranted(true) }
    public func denyWeights() { traffic.setGranted(false) }

    /// Whether the phone path can actually run. False means the App layer handed over no library — no
    /// storage, or no wiring on this build — which is a fact to state, not a button to disable silently.
    public var offersPhone: Bool { library != nil }
    public var offersServer: Bool {
        guard let servers, servers.profile != nil else { return false }
        return servers.offersLifecycle
    }

    public var isDownloading: Bool { task != nil || serverPullIsInFlight }

    /// The cards to draw, in the chosen order, with a typed name offered as its own card when the
    /// library does not carry it.
    public var visibleRows: [LocalCatalogRow] {
        ModelCatalogQuery.rows(rows, filter: filter, origin: destination)
    }

    public func choose(_ destination: ModelCatalogOrigin) async {
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
        if destination.landsOnThisPhone {
            rows = ModelCatalog.onDevice
            guard let library else { return }
            do {
                rows = try await library.catalogRows()
            } catch {
                // The curated list stays on screen with its installed marks missing rather than
                // emptying the tab: "no models" would be a claim nobody checked.
                notice = error.localizedDescription
            }
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

    /// The transfer state for one card, or nil when nothing is in flight for it.
    ///
    /// The server numbers are read from `ModelManagerModel` here rather than copied into this type: the
    /// server's own progress is its truth, and a second copy of it is a second thing to keep honest.
    public func status(for row: LocalCatalogRow) -> ModelTransferStatus? {
        if row.origin.landsOnThisPhone {
            guard let status = phoneStatus, status.entryID == row.id else { return nil }
            return status
        }
        guard pulledID == row.id, let progress = servers?.pullProgress else { return nil }
        return ModelTransferStatus(entryID: row.id, pull: progress)
    }

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

    /// Why the phone path refuses to start, in the sheet's and the notice's shared words. It names what
    /// has to be turned on rather than only refusing, because a button that does nothing and says nothing
    /// reads as a broken app.
    public static let trafficNotice = "Downloading a model sends bytes off this device. Turn on model "
        + "downloads, and Cairn will show the outbound badge while the weights are in flight."

}
