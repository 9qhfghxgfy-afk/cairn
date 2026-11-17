import Foundation

/// How one file fetch ended.
///
/// `.paused` carries the resume block the system hands back, and it is the reason pause/resume is
/// real rather than a restart: the bytes already transferred are never thrown away, and a resumed
/// file still has to hash to the published digest before it counts as installed.
public enum ModelDownloadOutcome: Sendable, Equatable {
    case complete(bytes: Int64)
    case paused(resumeData: Data)
    case failed(message: String)
}

public struct DownloadProgressUpdate: Sendable, Equatable {
    public var receivedBytes: Int64
    /// nil when the server did not say how large the file is. Progress then shows bytes, not a
    /// percentage, because a guessed denominator is a lie about how close the download is.
    public var expectedBytes: Int64?

    public init(receivedBytes: Int64, expectedBytes: Int64?) {
        self.receivedBytes = receivedBytes
        self.expectedBytes = expectedBytes
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
}
