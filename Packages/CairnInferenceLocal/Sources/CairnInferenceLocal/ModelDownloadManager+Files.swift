import Foundation

/// The per-file half of the download manager: one file, fetched or picked up from a resume block, and then
/// weighed against the digest the publisher stated for it.
///
/// Split from the actor that decides what counts as installed because the two halves answer different
/// questions. That half asks when a repository may be called installed — opt-in, a listing, a manifest, the
/// order of writes. This half asks what happens to a single file that stopped halfway, and the answers are
/// about a connection, a temporary file this process does not own, and a checksum that must still be proved
/// at the end no matter how many times the file was started over.
extension ModelDownloadManager {
    enum FileResult: Sendable, Equatable {
        case verified(InstalledModelFile)
        case paused(name: String)
        case cancelled(name: String)
        case failed(ModelDownloadFailure)
    }

    func fetch(
        _ file: ModelFileDescriptor,
        repoID: String,
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async -> FileResult {
        onEvent(.fileStarted(name: file.name))
        let destination = layout.directory(for: repoID).appendingPathComponent(file.name)

        let progress: @Sendable (DownloadProgressUpdate) -> Void = { update in
            // A parked connection is its own event, not a progress tick. Reported as progress, the bar
            // would move on the screen while nothing moved on the wire; reported as nothing, the screen
            // would sit still and give no reason. Both are worse than the truth.
            if update.isWaiting {
                onEvent(.waiting(name: file.name))
            } else {
                onEvent(.fileProgress(name: file.name, update: update))
            }
        }
        let outcome = await transfer(file: file, to: destination, repoID: repoID, onProgress: progress)

        switch outcome {
        case .paused(let resumeData):
            if resumeData.isEmpty { resumeStore.clear(repoID: repoID, file: file.name) }
            else { resumeStore.save(resumeData, repoID: repoID, file: file.name) }
            onEvent(.paused(name: file.name))
            return .paused(name: file.name)

        case .cancelled:
            // Given up on, so the resume block goes first: it is the part that would come back as a later
            // attempt resuming from bytes whose verification record has been forgotten. The file itself is
            // the caller's to discard, because only that caller knows whether a directory holding a manifest
            // is debris. No event is emitted — a cancel is not something that happened to this download.
            resumeStore.clear(repoID: repoID, file: file.name)
            return .cancelled(name: file.name)

        case .failed:
            onEvent(.failed(message: ModelDownloadFailure.transferFailed.message))
            return .failed(.transferFailed)

        case .complete(let bytes):
            // A published digest must match. An unpublished one is recorded as unverified rather
            // than treated as a pass, so the Installed tab can say so.
            let published = (file.sha256?.isEmpty == false) ? file.sha256 : nil
            let verified = published.map { SHA256Digest.matches(expected: $0, fileAt: destination) } ?? false
            if published != nil, !verified {
                // The bytes are wrong, so nothing about this file is worth keeping — including the block
                // a pause would otherwise hand to the next attempt.
                resumeStore.clear(repoID: repoID, file: file.name)
                onEvent(.failed(message: ModelDownloadFailure.verificationFailed.message))
                return .failed(.verificationFailed)
            }
            onEvent(.fileFinished(name: file.name, verified: verified))
            return .verified(InstalledModelFile(name: file.name, bytes: bytes, sha256: published))
        }
    }

    /// One file, picked up where a pause left it whenever a resume block survived.
    private func transfer(
        file: ModelFileDescriptor,
        to destination: URL,
        repoID: String,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        guard let resumeData = resumeStore.load(repoID: repoID, file: file.name) else {
            return await downloader.fetch(file, to: destination, onProgress: onProgress)
        }
        let resumed = await downloader.resume(using: resumeData, to: destination, onProgress: onProgress)
        switch resumed {
        case .complete, .paused, .cancelled:
            return resumed
        case .failed:
            // A resume block points into a temporary file the system owns and is free to reclaim, and
            // after a launch it usually has been. That is not the download failing — it is one file that
            // has to be taken again from its beginning.
            //
            // Failing here instead would leave a repository stuck on a block nothing can use, every retry
            // ending the same way, which is how a model becomes impossible to download on a phone with
            // plenty of room left. The block is cleared before the retry so the fresh fetch cannot pick it
            // up again, and the bytes are still weighed against the published digest afterwards: a restart
            // costs time, never correctness.
            resumeStore.clear(repoID: repoID, file: file.name)
            return await downloader.fetch(file, to: destination, onProgress: onProgress)
        }
    }
}
