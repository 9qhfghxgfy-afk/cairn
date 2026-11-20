import Foundation

/// The on-device model library, as data.
///
/// Cairn has always been able to download a model to the phone — `CairnInferenceLocal` has the
/// catalogue, the downloader, the checksum and the store layout — and no screen ever showed any of
/// it, so a person opening "Model Manager" found a server's model list and nothing to tap. These
/// types are the seam the App layer implements against, in the same shape `OnDeviceEngineReport`
/// already uses: the runtime stays on one side, the view reads plain values on the other, and no
/// view can call a downloader.
///
/// Sizes travel as bytes and are formatted by the view, because "8.2 GB" written here would be a
/// string a test cannot check the arithmetic of.
///
/// `LocalCatalogRow`, the row the Download list is built from, lives in its own file.

/// A model this phone already holds.
public struct InstalledLocalModel: Identifiable, Sendable, Equatable {
    public var repoID: String
    public var displayName: String
    public var sizeBytes: Int64
    public var fileCount: Int
    public var installedOn: Date
    /// Whether Cairn can remove it. Apple's system model is installed and evicted by iOS, so its row
    /// says so instead of offering a Delete button that would do nothing.
    public var canDelete: Bool

    public init(
        repoID: String,
        displayName: String,
        sizeBytes: Int64 = 0,
        fileCount: Int = 0,
        installedOn: Date = Date(timeIntervalSince1970: 0),
        canDelete: Bool = true
    ) {
        self.repoID = repoID
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.installedOn = installedOn
        self.canDelete = canDelete
    }

    public var id: String { repoID }
}

/// How one download is going, as the screen reads it.
///
/// `file` names what is being fetched right now, because a phone pulling six files and a phone pulling
/// one 4 GB weight look identical without it — and the one thing a person staring at a stalled bar wants
/// to know is which file the app is sitting on. It is optional because a server pull never names a file
/// and a repository whose listing arrived without names has nothing honest to say.
///
/// `paused` is its own case rather than `stopped`, because the two mean different things to the hand
/// reaching for the screen: a pause keeps every byte already fetched on the phone and can be picked up
/// again from where it stopped, while a cancel throws the partial file away. Showing one as the other is
/// how a person ends up either waiting for a transfer that is not running or throwing away 3 GB of
/// progress they meant to keep.
public enum LocalTransferState: Sendable, Equatable {
    case queued
    case waiting(doneBytes: Int64, totalBytes: Int64?, file: String? = nil)
    case running(doneBytes: Int64, totalBytes: Int64?, file: String? = nil)
    case paused(doneBytes: Int64, totalBytes: Int64?, file: String? = nil)
    case verifying
    case installed(bytes: Int64)
    case stopped
    case failed(String)

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .waiting: return "Waiting for the network"
        case .running: return "Downloading"
        case .paused: return "Paused"
        case .verifying: return "Checking the checksum"
        case .installed: return "Installed on this phone"
        case .stopped: return "Stopped"
        case .failed(let reason): return reason
        }
    }

    /// The file this transfer is sitting on, when it has one.
    public var fileName: String? {
        switch self {
        case .waiting(_, _, let file), .running(_, _, let file), .paused(_, _, let file): return file
        default: return nil
        }
    }

    /// nil when no total was ever stated — the row then draws an open-ended bar instead of a 0% bar
    /// that claims to know how far it has to go.
    public var fraction: Double? {
        let bytes: (done: Int64, total: Int64?)
        switch self {
        case .waiting(let done, let total, _): bytes = (done, total)
        case .running(let done, let total, _): bytes = (done, total)
        case .paused(let done, let total, _): bytes = (done, total)
        default: return nil
        }
        guard let total = bytes.total, total > 0 else { return nil }
        return min(1, Double(bytes.done) / Double(total))
    }

    /// True while bytes are expected to move. A pause is not in flight — nothing is moving — but it keeps
    /// its numbers, which is what lets the sheet draw the same bar with a Resume button under it. A wait
    /// is in flight: the connection is being retried and the transfer has not been given up on.
    public var isInFlight: Bool {
        switch self {
        case .queued, .waiting, .running, .verifying: return true
        case .paused, .installed, .stopped, .failed: return false
        }
    }
}

/// The engine a mode or a tap points the chat at.
public struct EngineChoice: Identifiable, Sendable, Equatable {
    public var engineID: String
    public var name: String
    public var id: String { engineID }

    public init(engineID: String, name: String) {
        self.engineID = engineID
        self.name = name
    }
}

/// What the library screen can do, behind a boundary the App layer implements.
///
/// Streams rather than completion handlers so the screen can show progress and Stop can cancel the
/// task that holds the connection. Nothing here returns a byte of model content: a download reports
/// sizes and states, never file contents, which keeps a model file out of every log.
///
/// `@MainActor` because every conformer's job is feeding one screen, and because the real one hands
/// back a stream whose task the view model has to own. The bytes still move off the main actor,
/// inside the downloader, where they already do.
@MainActor
public protocol LocalModelLibraryServicing: Sendable {
    /// The curated list, with `isInstalled` already settled against what is on disk.
    func catalogRows() async throws -> [LocalCatalogRow]
    func installedRows() async throws -> [InstalledLocalModel]
    /// Pulls one repository to the phone. The stream ends when the transfer ends; the caller owns
    /// the task, so cancelling it is what closes the connection.
    func download(_ row: LocalCatalogRow) -> AsyncThrowingStream<LocalTransferState, any Error>
    /// Asks a running transfer to stop and keep every byte already fetched, so the next `download` of that
    /// repository carries on from the same offsets instead of starting again. Does nothing when nothing is in
    /// flight — a row cannot be put into Paused from nothing, and a screen that offers Pause for a transfer
    /// that is not running is a button that lies.
    func pauseDownload(repoID: String) async
    /// Stops a running transfer and takes the space back: the resume blocks and whatever landed before the
    /// stop, down to the point where the repository is this phone's again.
    func cancelDownload(repoID: String) async throws
    /// Throws away everything a cancelled transfer left behind: the partial files and the resume blocks
    /// that point into them. A pause keeps them; a cancel must not. A half-file whose resume block
    /// survives is the state that lets the next download of that repository pick up from bytes nobody
    /// vouched for, so this runs when the person says Cancel rather than being left for the next launch.
    func discard(repoID: String) async throws
    /// True when this phone is holding the bytes of a transfer that is not running — a pause, or a
    /// download that ended when the app did. The screen asks so it can offer Resume rather than a fresh
    /// Download that quietly picks the kept bytes back up: progress nobody mentions is how a person ends
    /// up deleting a model and re-fetching four gigabytes they already had.
    func keepsPartialTransfer(repoID: String) async -> Bool
    func delete(_ model: InstalledLocalModel) async throws
}