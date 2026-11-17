import Foundation
import Testing
@testable import CairnInferenceLocal

/// Records what a test observed, in order, from any thread.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock(); entries.append(entry); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }; return entries
    }
}

/// A download transport whose behaviour is dictated per file name, so pause, resume, and a bad
/// checksum can be exercised with no network and no simulator.
struct StubDownloader: ModelFileDownloading {
    let outcomes: [String: ModelDownloadOutcome]
    let payload: Data
    let calls: Recorder

    func fetch(
        _ file: ModelFileDescriptor,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        calls.record("fetch:\(file.name)")
        try? payload.write(to: destination, options: .atomic)
        return outcomes[file.name] ?? .complete(bytes: Int64(payload.count))
    }

    func resume(
        using resumeData: Data,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        calls.record("resume:\(resumeData.count)")
        try? payload.write(to: destination, options: .atomic)
        return .complete(bytes: Int64(payload.count))
    }
}
