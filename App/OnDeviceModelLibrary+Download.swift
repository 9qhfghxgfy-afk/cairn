import Foundation
import CairnChatDomain
import CairnInferenceLocal

/// The download half of the phone's own library: a published listing, a manager that verifies every byte
/// against it, and a stream of states the Download sheet draws.
///
/// Nothing here invents progress. The denominator is whatever the publisher's own listing states; if the
/// listing states nothing, the row draws an open-ended bar. Byte counts for finished files are summed from
/// the listing rather than from the downloader's own running total, because the manager reports progress per
/// file and the screen needs the repository's total — adding the two together would show a number that is
/// neither.
extension OnDeviceModelLibrary {
    func download(_ row: LocalCatalogRow) -> AsyncThrowingStream<LocalTransferState, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                await self?.run(row: row, continuation: continuation)
            }
            // Whoever stops reading the stream owns the connection. Closing the sheet cancels the task,
            // which is what actually stops the transfer; dropping the loop alone would not.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func run(
        row: LocalCatalogRow,
        continuation: AsyncThrowingStream<LocalTransferState, any Error>.Continuation
    ) async {
        guard let layout else {
            continuation.yield(.failed(CairnLibraryError.noStorage.errorDescription ?? "no storage"))
            continuation.finish()
            return
        }
        continuation.yield(.queued)
        let listing: [ModelFileListing]
        do {
            listing = try await fetchListing(row.repoID)
        } catch {
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
            return
        }
        guard !listing.isEmpty else {
            continuation.yield(.failed("This repository has no readable file list."))
            continuation.finish()
            return
        }
        // Frozen before the event closure: a `var` captured by a `@Sendable` closure is an error under
        // strict concurrency even when nothing mutates it afterwards, and a model's file list is exactly
        // the kind of thing someone later "just tweaks" into a loop that does mutate it.
        let statedBytes: [String: Int64] = listing.reduce(into: [:]) { sizes, file in
            sizes[file.name] = file.bytes ?? 0
        }
        let tally = TransferTally()
        let manager = ModelDownloadManager(
            downloader: downloader,
            layout: layout,
            gate: OutboundGate(optedIn: traffic.isGranted())
        )
        let outcome = await manager.install(repoID: row.repoID, listing: listing) { event in
            switch event {
            case .planned(_, let total):
                tally.totalBytes = total
                continuation.yield(.running(doneBytes: tally.landed(), totalBytes: total))
            case .fileStarted:
                continuation.yield(.running(doneBytes: tally.landed(), totalBytes: tally.totalBytes))
            case .fileProgress(_, let update):
                tally.received = update.receivedBytes
                continuation.yield(.running(doneBytes: tally.landed(), totalBytes: tally.totalBytes))
            case .fileFinished(let name, _):
                tally.land(statedBytes[name] ?? 0)
                continuation.yield(.running(doneBytes: tally.landed(), totalBytes: tally.totalBytes))
            case .paused:
                // A pause keeps the bytes for a later resume. `LocalTransferState` has no pause, and the
                // honest reading is "Stopped" — not a failure, because nothing went wrong.
                continuation.yield(.stopped)
            case .completed(let bytes):
                continuation.yield(.installed(bytes: bytes))
            case .failed(let message):
                continuation.yield(.failed(message))
            }
        }
        switch outcome {
        case .installed(let bytes):
            continuation.yield(.installed(bytes: bytes))
        case .paused:
            continuation.yield(.stopped)
        case .failed(let failure):
            continuation.yield(.failed(failure.message))
        }
        continuation.finish()
    }
}

/// The running total, kept outside the event closure so the numbers add up the same way on every event.
///
/// The manager calls this closure from its own actor, one event at a time, so the mutable state is not
/// raced; `@unchecked Sendable` records that fact rather than pretending the type is value-shaped.
private final class TransferTally: @unchecked Sendable {
    var totalBytes: Int64?
    var landedBytes: Int64 = 0
    var received: Int64 = 0

    func land(_ bytes: Int64) {
        landedBytes += bytes
        received = 0
    }

    func landed() -> Int64 { landedBytes + received }
}
