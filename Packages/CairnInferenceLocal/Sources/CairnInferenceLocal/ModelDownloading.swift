import Foundation

/// How one file fetch ended.
///
/// `.paused` carries the resume block the system hands back, and it is the reason pause/resume is
/// real rather than a restart: the bytes already transferred are never thrown away, and a resumed
/// file still has to hash to the published digest before it counts as installed.
///
/// `.cancelled` is the other half of the same distinction and it is not a pause: the person asked for the
/// transfer to be given up on, so nothing about it is worth keeping and no resume block is returned. It is
/// not a failure either — the transfer stopped because it was told to, and reporting it as a failure would
/// offer a message about a download nobody had a problem with.
public enum ModelDownloadOutcome: Sendable, Equatable {
    case complete(bytes: Int64)
    case paused(resumeData: Data)
    case cancelled
    /// The server answered a refusal, and the number is kept rather than flattened into a sentence.
    ///
    /// A 401 and a 404 need different things from the person reading the sheet — one wants a token, the other
    /// wants a different repository — and a download task reports both as a finished transfer with no error, so
    /// the status is the only fact that distinguishes them. It is typed metadata: no URL, no header, no body.
    case refused(status: Int)
    case failed(message: String)
}


public struct DownloadProgressUpdate: Sendable, Equatable {
    public var receivedBytes: Int64
    /// nil when the server did not say how large the file is. Progress then shows bytes, not a
    /// percentage, because a guessed denominator is a lie about how close the download is.
    public var expectedBytes: Int64?
    /// True when the transfer is parked rather than moving: the system is holding the connection and
    /// waiting for a route back to the network. The byte counts in a waiting update are the last honest
    /// ones, never a guess — a wait adds nothing and erases nothing, so a bar parked at 2.1 GB is still
    /// a bar that says 2.1 GB.
    public var isWaiting: Bool

    public init(receivedBytes: Int64, expectedBytes: Int64?, isWaiting: Bool = false) {
        self.receivedBytes = receivedBytes
        self.expectedBytes = expectedBytes
        self.isWaiting = isWaiting
    }

    public var fraction: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }
}

/// The seam the download manager works against, so the plan/verify/resume logic is unit-testable
/// with no network and no simulator.
public protocol ModelFileDownloading: Sendable {
    func fetch(
        _ file: ModelFileDescriptor,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome

    func resume(
        using resumeData: Data,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome

    /// Stops the transfers writing files inside `directory`, which is the store's directory for one
    /// repository, and reports how many it stopped.
    ///
    /// The directory is the key because it is the only thing both sides know: the caller holds a repository
    /// name and this layer holds the file it is writing, and the store's layout is what maps one to the
    /// other. Passing a repository name down here instead would put the store's naming scheme inside a
    /// transfer type, which has no business knowing it.
    ///
    /// `pause` decides what the stop is worth. A pause asks the system for the resume block that lets the
    /// same bytes be picked up later; a cancel asks for nothing to be kept. Both close the connection now
    /// rather than at the next gap between bytes, which is the difference between a Pause button that works
    /// and one that takes effect six gigabytes later.
    func stopTransfers(in directory: URL, pause: Bool) -> Int
}

/// A downloader that cannot stop a transfer in the middle is still a downloader, and a test double should
/// not be made to invent a connection in order to satisfy this boundary. The no-op is honest about what it
/// means: a Pause button backed by a downloader like this one does nothing to the bytes, which is exactly
/// what the double is checking.
public extension ModelFileDownloading {
    func stopTransfers(in directory: URL, pause: Bool) -> Int { 0 }
}
