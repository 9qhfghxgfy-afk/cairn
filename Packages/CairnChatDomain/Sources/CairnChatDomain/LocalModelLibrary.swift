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
public enum LocalTransferState: Sendable, Equatable {
    case queued
    case running(doneBytes: Int64, totalBytes: Int64?)
    case verifying
    case installed(bytes: Int64)
    case stopped
    case failed(String)

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Downloading"
        case .verifying: return "Checking the checksum"
        case .installed: return "Installed on this phone"
        case .stopped: return "Stopped"
        case .failed(let reason): return reason
        }
    }

    /// nil when no total was ever stated — the row then draws an open-ended bar instead of a 0% bar
    /// that claims to know how far it has to go.
    public var fraction: Double? {
        guard case .running(let done, let total) = self, let total, total > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }

    public var isInFlight: Bool {
        switch self {
        case .queued, .running, .verifying: return true
        default: return false
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
    func delete(_ model: InstalledLocalModel) async throws
}