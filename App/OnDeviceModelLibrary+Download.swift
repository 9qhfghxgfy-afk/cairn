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
            case .fileStarted(let name):
                continuation.yield(
                    .running(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name)
                )
            case .waiting(let name):
                // Nothing is moving and the reason is known, so the row says so with its numbers frozen
                // where they stand. The alternative was silence, and silence on a stalled four-gigabyte
                // transfer is what makes people kill a download that was going to carry on by itself.
                continuation.yield(
                    .waiting(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name)
                )
            case .fileProgress(let name, let update):
                tally.received = update.receivedBytes
                continuation.yield(
                    .running(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name)
                )
            case .fileFinished(let name, _):
                tally.land(statedBytes[name] ?? 0)
                continuation.yield(
                    .running(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name)
                )
            case .paused(let name):
                // A pause keeps every byte fetched and the blocks that point at them, so it is reported as
                // a pause with its numbers attached — not as `stopped`, which is what the screen used to
                // say about a transfer a person could still resume.
                continuation.yield(
                    .paused(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name)
                )
            case .completed(let bytes):
                continuation.yield(.installed(bytes: bytes))
            case .failed(let message):
                continuation.yield(.failed(message))
            }
        }
        switch outcome {
        case .installed(let bytes):
            continuation.yield(.installed(bytes: bytes))
        case .paused(let name):
            continuation.yield(.paused(doneBytes: tally.landed(), totalBytes: tally.totalBytes, file: name))
        case .cancelled:
            // Stopped, and nothing kept. The stage's own word for this is "Cancelled", which is what the
            // sheet shows; the state is `stopped` because there is nothing left to say about a transfer that
            // was given up on, and no number worth carrying forward.
            continuation.yield(.stopped)
        case .failed(let failure):
            continuation.yield(.failed(failure.message))
        }
        continuation.finish()
    }

    /// Asks a running transfer to stop and keep everything it has fetched.
    ///
    /// Nothing is said about the row here, and nothing should be: the manager's own `paused` state travels
    /// back down the stream this call is ending, and it is the one holding the byte counts. What the App
    /// layer decides is only that a pause has to exist, which is a fact about a phone carrying four
    /// gigabytes of weights and a person with a train to catch.
    func pauseDownload(repoID: String) async {
        guard let layout else { return }
        _ = await stopTransfer(repoID: repoID, layout: layout, pause: true)
    }

    /// Stops a transfer and takes the space back.
    ///
    /// The connection closes before anything is deleted. A task still writing while its blocks are being
    /// removed is a task that can put one back, and a leftover resume block is the exact state this path
    /// exists to prevent: the next attempt would carry on from bytes whose verification record is gone.
    func cancelDownload(repoID: String) async throws {
        guard let layout else { throw CairnLibraryError.noStorage }
        _ = await stopTransfer(repoID: repoID, layout: layout, pause: false)
        try await discard(repoID: repoID)
    }

    /// Throws away what a cancelled transfer left: the resume blocks and whatever landed before the cancel.
    func discard(repoID: String) async throws {
        guard let layout else { throw CairnLibraryError.noStorage }
        // The rule about what a stopped transfer may leave behind belongs to the manager that wrote it. That
        // is the type which knows a directory holding a manifest is an installed model rather than debris,
        // and duplicating the test here is how the two halves start disagreeing about what "cancelled"
        // deletes.
        await manager(for: layout).discardPartial(repoID: repoID)
    }

    /// Whether this phone is holding a transfer that is not running.
    ///
    /// Asked of the resume store rather than remembered in memory, so the answer survives the app being
    /// killed: a download interrupted by iOS is exactly the case where nobody was there to press Pause, and
    /// the bytes kept through it are worth offering back.
    func keepsPartialTransfer(repoID: String) async -> Bool {
        guard let layout else { return false }
        return ModelResumeStore.forStore(layout).hasBlocks(repoID: repoID)
    }

    private func stopTransfer(repoID: String, layout: ModelStoreLayout, pause: Bool) async -> Int {
        await manager(for: layout).stopTransfers(repoID: repoID, pause: pause)
    }

    /// A manager pointed at one repository.
    ///
    /// Built per call rather than kept: an actor's state is the set of files it has decided are installed,
    /// and a long-lived one would be a cache of that decision outliving the download that made it. The gate
    /// is always shut on this path — stopping and discarding send no request, and a manager handed permission
    /// to download is a manager that could be handed a download by mistake.
    private func manager(for layout: ModelStoreLayout) -> ModelDownloadManager {
        ModelDownloadManager(
            downloader: downloader,
            layout: layout,
            gate: OutboundGate(optedIn: false)
        )
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
