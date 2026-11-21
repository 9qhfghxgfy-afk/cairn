import Foundation

/// Routes URLSession download delegate callbacks back to the call that started the task.
///
/// The token travels on `taskDescription`, so a callback always finds the waiter that started its
/// own task even when several files are in flight. State is guarded by a lock rather than an actor
/// because the delegate callbacks are synchronous and their ordering matters: a progress callback
/// that lands after its task finished must not be re-sequenced behind it.
///
/// **`URLSessionDownloadDelegate` has to be named on this declaration, and that is not a style choice.**
/// URLSession dispatches a delegate callback by asking the delegate object whether it answers a selector, and
/// Swift hands a method to the Objective-C runtime only when it satisfies a protocol the class actually
/// declares. `URLSessionDataDelegate` inherits `URLSessionTaskDelegate` and not `URLSessionDownloadDelegate`,
/// so a bridge naming only the data protocol keeps `didWriteData` and `didFinishDownloadingTo` as ordinary
/// Swift methods the session never sees: they compile, they read correctly, they never run. That is the whole
/// of the iPhone stall this file used to cause — the metadata files finished and added up to about a kilobyte,
/// the weight file streamed into a temporary file with no progress callback delivered and no handoff to move it
/// into the store, and the bar sat parked at 1 KB of four gigabytes. Measured rather than argued: the same code
/// declaring only the data protocol reported a completion with no write and no finish callback, while the same
/// code declaring `URLSessionDownloadDelegate` delivered the write, the file, and the status.
///
/// The callbacks themselves are thin adapters in `DownloadBridge+Delegate.swift`. Every decision about a
/// waiter's state lives here, so the rules can be tested without a session.
///
/// Only byte counts, tokens and status codes are ever touched here — no prompt text, no file contents, and no
/// URL beyond the host comparison the redirect rule needs.
final class DownloadBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Why this process asked for a transfer to stop, as distinct from a route dropping or the surrounding
    /// task being cancelled. The two are worth different things: a pause wants the resume block the system
    /// produces, a cancel wants nothing kept.
    enum StopMode: Sendable, Equatable { case pause, cancel }

    /// The least number of bytes that must arrive before another progress update is worth sending.
    ///
    /// A four-gigabyte weight file reports a write every few hundred kilobytes, which is thousands of events
    /// per transfer. Each one crosses into the view model and redraws a bar nobody can read that fast, and the
    /// flood costs socket time — a progress stream that outruns the screen is how a fast download looks slow.
    static let progressByteStride: Int64 = 256 * 1024
    /// The longest a bar may sit still while bytes are genuinely arriving.
    ///
    /// The byte stride alone would leave a slow line silent for a quarter of a gigabyte, which reads as a hang;
    /// the time ceiling alone would make a fast one redraw every packet. Both together give a screen that moves
    /// about four times a second at any speed.
    static let progressIntervalNanoseconds: UInt64 = 250_000_000

    private struct Waiter {
        let destination: URL
        let onProgress: @Sendable (DownloadProgressUpdate) -> Void
        // The download-task type, not the base one: the pause path needs the variant of cancel that asks for
        // the resume block to be kept, and that variant belongs to the download task. Every task registered
        // here is one — the downloader only ever attaches the task it is running.
        var task: URLSessionDownloadTask?
        var continuation: CheckedContinuation<ModelDownloadOutcome, Never>?
        var finished = false
        /// The largest byte count this task has reported. A waiting update repeats it rather than
        /// reading the task's own counter, which can lag a write that has not landed yet — a bar that
        /// slides backwards mid-download reads as a corrupted file, and the number would be wrong.
        var reportedBytes: Int64 = 0
        /// The byte count the last emitted update carried, which is where the next window is measured from.
        /// Measuring from the newest write instead would make a window one buffer wide, and the throttle would
        /// throttle nothing.
        var sentBytes: Int64 = 0
        /// When the last update went out, on the monotonic clock. A wall clock that steps back mid-transfer —
        /// a time sync during a four-gigabyte pull is a normal thing — would otherwise stall the bar.
        var sentAtNanos: UInt64?
        /// nil until something in this app presses Pause or Cancel on this file. A stop that came from
        /// anywhere else keeps the older behaviour, which is to hand back a resume block whenever the
        /// system offers one.
        var stopMode: StopMode?
        /// The resume block a pause's cancellation handed back, filed here until the guaranteed completion
        /// callback is ready to answer with it. See `recordPauseBlock`.
        var pauseBlock: Data?
        /// An answer that arrived before `wait(for:)` had installed its continuation.
        ///
        /// The task is started before the call site reaches `wait`, and a refusal for a bad URL or a refused
        /// scheme can come back in microseconds — faster than the code that asked for the file gets to ask for
        /// its result. An answer with nowhere to go is an answer that never arrives: the waiter is already
        /// marked finished, so the continuation resumes with nothing of its own and a 404 reaches the sheet
        /// wearing whatever sentence the fallback happens to carry. Filing it here means the first thing
        /// `wait` does is hand back the real reason.
        var pendingOutcome: ModelDownloadOutcome?
    }

    private let lock = NSLock()
    private var waiters: [Int: Waiter] = [:]
    private var nextToken = 0

    func register(destination: URL, onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void) -> Int {
        lock.lock()
        defer { lock.unlock() }
        nextToken += 1
        waiters[nextToken] = Waiter(destination: destination, onProgress: onProgress)
        return nextToken
    }

    func attach(_ token: Int, task: URLSessionDownloadTask) {
        _ = update(token) { $0.task = task }
    }

    func cancel(_ token: Int) {
        lock.lock()
        let task = waiters[token]?.task
        lock.unlock()
        task?.cancel()
    }

    /// Stops every transfer whose file is being written inside `directory`, and returns how many.
    ///
    /// `pause` decides what the stop is worth, and the distinction is the whole reason this exists: a Pause
    /// button that throws the resume block away is a Download button with an extra tap, and a Cancel button
    /// that keeps the block leaves a repository whose next attempt resumes from bytes nobody verified.
    ///
    /// The tasks are cancelled after the lock is released. `cancel` re-enters URLSession, whose completion
    /// callback can arrive on another queue and take this same lock — a lock held across a callback that
    /// calls back in is how a download dies with the screen frozen rather than with a message.
    func stopTransfers(in directory: URL, pause: Bool) -> Int {
        let mode: StopMode = pause ? .pause : .cancel
        var stopped: [URLSessionDownloadTask] = []
        lock.lock()
        let matching = waiters
            .filter { !$0.value.finished && owns(destination: $0.value.destination, in: directory) }
            .map { $0.key }
        for token in matching {
            guard var waiter = waiters[token], !waiter.finished else { continue }
            waiter.stopMode = mode
            waiters[token] = waiter
            if let task = waiter.task { stopped.append(task) }
        }
        lock.unlock()
        for task in stopped {
            if mode == .pause {
                // The documented verb for "stop, and tell me what a later attempt needs". A plain `cancel`
                // makes no such request, so the block would be whatever the system felt like producing.
                //
                // The block arrives on this completion handler, and a matching error arrives on
                // `didCompleteWithError`; which comes first is not stated anywhere, so both are wired to the
                // same waiter and the first one to answer wins — `resolve` ignores a waiter that has already
                // been answered, so one transfer gets exactly one outcome and two chances to keep its bytes.
                let token = task.taskDescription.flatMap { Int($0) }
                task.cancel(byProducingResumeData: { [weak self] data in
                    guard let self, let token else { return }
                    self.recordPauseBlock(token: token, resumeData: data)
                })
            } else {
                // A cancel asks for nothing, which is the point: a resume block is a promise about bytes this
                // app is about to delete, and a promise that outlives them is worse than no promise.
                task.cancel()
            }
        }
        return stopped.count
    }

    /// Files away the resume block a pause's cancellation produced, without answering the transfer.
    ///
    /// A pause produces two callbacks and Apple states no order between them: the block comes on this
    /// completion handler, the matching error arrives on `didCompleteWithError`. Answering from whichever got
    /// there first is how four gigabytes get thrown away by a race nobody can see — the one that arrives
    /// first may be the one carrying nothing. So this stores, and `answer(token:failure:)` answers, because
    /// that callback is documented always to come. It takes the best block it can see: the one filed here if
    /// it has landed, else the one on its own error, else nothing, which means the next attempt starts this
    /// file over and still hashes it at the end.
    private func recordPauseBlock(token: Int, resumeData: Data?) {
        guard let resumeData, !resumeData.isEmpty else { return }
        _ = update(token) { waiter in
            if waiter.pauseBlock == nil { waiter.pauseBlock = resumeData }
        }
    }

    /// Whether a file being written is one of this repository's. The store keeps a repository's files in one
    /// directory, so the parent of a destination is the repository — compared on standardised paths, because
    /// a bookmark's URL and a constructed one are the same place written two different ways.
    private func owns(destination: URL, in directory: URL) -> Bool {
        destination.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
    }

    /// The answer to the transfer this token was reserved for.
    ///
    /// Installed after the task starts, which is the order the caller has to use: register, attach, resume,
    /// wait. That order leaves one hole, and `pendingOutcome` is what closes it — a refusal can be delivered
    /// before this method runs, and an answer that arrives with no continuation waiting for it would otherwise
    /// be lost, leaving the caller to report a reason it did not witness.
    func wait(for token: Int) async -> ModelDownloadOutcome {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                guard var waiter = waiters[token] else {
                    lock.unlock()
                    continuation.resume(returning: .failed(message: "The download ended before it started."))
                    return
                }
                if let early = waiter.pendingOutcome {
                    // The honest answer got here first. It is returned as it stands, and the waiter goes with it.
                    waiters.removeValue(forKey: token)
                    lock.unlock()
                    continuation.resume(returning: early)
                    return
                }
                guard !waiter.finished, waiter.continuation == nil else {
                    waiters.removeValue(forKey: token)
                    lock.unlock()
                    continuation.resume(returning: .failed(message: "The download ended before it started."))
                    return
                }
                waiter.continuation = continuation
                waiters[token] = waiter
                lock.unlock()
            }
        } onCancel: {
            // Cancelling the URLSession task is what yields a resume block, so a cancelled download
            // can be picked up again instead of starting from the beginning.
            cancel(token)
        }
    }

    // MARK: - What the delegate adapters ask this bridge to decide
    //
    // The callbacks in `DownloadBridge+Delegate.swift` read a task and call one of these. Every rule — when a
    // progress number is worth sending, whether a response is a file, what a cancellation means — is here, so
    // each one can be exercised without a session, a socket, or a simulator.

    /// Records one write and sends a progress update when the window says it is worth sending one.
    func emitProgress(token: Int, received: Int64, expectedFromServer: Int64) {
        guard let waiter = read(token), !waiter.finished else { return }
        let due = update(token) { state -> Bool in
            // A hop that restarts — a redirect followed, a retry taken — starts its counter over. Measuring
            // the window from the last number sent would then read as a negative stride and go quiet, so a
            // counter that went backwards is treated as a new window measured from zero.
            let window = received >= state.sentBytes ? received - state.sentBytes : received
            let now = DispatchTime.now().uptimeNanoseconds
            let idle = state.sentAtNanos.map { now > $0 ? now - $0 : 0 } ?? UInt64.max
            guard state.sentAtNanos == nil
                || window >= Self.progressByteStride
                || idle >= Self.progressIntervalNanoseconds
            else { return false }
            state.sentBytes = received
            state.sentAtNanos = now
            if received > state.reportedBytes { state.reportedBytes = received }
            return true
        }
        guard due == true else { return }
        waiter.onProgress(
            DownloadProgressUpdate(receivedBytes: received,
                                   expectedBytes: expectedFromServer > 0 ? expectedFromServer : nil)
        )
    }

    /// Sends the waiting state: nothing is moving, and the numbers are the last honest ones.
    func emitWaiting(token: Int, expectedFromServer: Int64) {
        guard let waiter = read(token), !waiter.finished else { return }
        waiter.onProgress(
            DownloadProgressUpdate(receivedBytes: waiter.reportedBytes,
                                   expectedBytes: expectedFromServer > 0 ? expectedFromServer : nil,
                                   isWaiting: true)
        )
    }

    /// Moves the system's temporary file into the store — or refuses it, which comes first.
    ///
    /// The status is read before a byte is moved, because a refusal is not a file: the Hub answers a bad path or
    /// a refused credential with a short body, and a download task reports that as a finished transfer with no
    /// error at all. Storing it is how `model.safetensors` ends up holding fourteen bytes of prose and a
    /// repository gets marked installed with nothing to load. URLSession deletes the temporary file as soon as
    /// this callback returns, so refusing here also discards the body — nothing of it is kept, and none of it is
    /// ever read.
    func storeFile(_ temporaryFile: URL, for token: Int, response: URLResponse?) {
        guard let waiter = read(token), !waiter.finished else { return }
        if let http = response as? HTTPURLResponse, !HTTPTransferStatus.carriesFile(http.statusCode) {
            resolve(token, with: .refused(status: http.statusCode))
            return
        }
        let target = waiter.destination
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temporaryFile, to: target)
        } catch {
            resolve(token, with: .failed(message: "The downloaded file could not be stored."))
        }
    }

    /// How many bytes a finished transfer left behind, read in every spelling Foundation uses.
    ///
    /// `FileAttributeKey.size` is not one type across platforms. The Foundation that ships with Xcode hands
    /// back an integer that bridges to `Int64`; the open-source one hands back a plain Swift `Int`, sometimes
    /// its unsigned twin; and a dynamic cast between two distinct Swift integer types fails rather than
    /// converting. A bare `as? Int64` therefore reads a real file as zero bytes on the open-source side, and
    /// in this position zero is never a wrong number — it is a completed four-gigabyte download announced as
    /// having delivered nothing, which throws
    /// away bytes and the digest that would have proved them. Measured, not assumed: that bare cast returned
    /// nothing for a fifteen-byte file on the toolchain this was edited on while the macOS runner reported a
    /// different count, and this machine cannot build the package to tell which side was right. So every
    /// spelling is asked in order and none is trusted, which is the only honest shape for a fact that is not
    /// verifiable here.
    private static func storedByteCount(atPath path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return 0 }
        let raw = attributes[.size]
        if let bytes = raw as? Int64 { return bytes }
        if let bytes = raw as? Int { return Int64(bytes) }
        if let bytes = raw as? UInt64 { return Int64(clamping: bytes) }
        if let number = raw as? NSNumber { return number.int64Value }
        return 0
    }

    /// Answers the one waiter this task belongs to, from the callback a transfer always produces.
    func answer(token: Int, failure: (any Error)?) {
        guard let waiter = read(token), !waiter.finished else { return }
        guard let failure else {
            // The size on disk, not the number the socket counted: a resumed file is the bytes that landed, and
            // the digest taken afterwards is what makes that claim true.
            let stored = Self.storedByteCount(atPath: waiter.destination.path)
            guard stored > 0 else {
                // A completion with no file behind it is not a completed download. The handoff callback is
                // documented to always precede this one, so reaching here means either the file never arrived or
                // something outside this app removed it between the two — and either way the honest answer is
                // that there is nothing to verify. Reporting bytes-zero as success would let the manager hash a
                // file that does not exist and call the failure a checksum problem.
                resolve(token, with: .failed(message: "The transfer finished without delivering a file."))
                return
            }
            resolve(token, with: .complete(bytes: stored))
            return
        }

        let nsError = failure as NSError
        let carried = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if nsError.code == NSURLErrorCancelled, waiter.stopMode == .cancel {
            // Given up on, so nothing that came out of this connection is kept — above all not the resume
            // block, which would let a later attempt carry on from bytes whose verification record has been
            // forgotten. The caller clears the file; this decides that the block never gets written.
            resolve(token, with: .cancelled)
            return
        }
        if nsError.code == NSURLErrorCancelled, waiter.stopMode == .pause {
            // The pause the person asked for, answered from the one callback a pause is documented always to
            // produce. A block filed from the other callback outranks the one on this error, and a pause with
            // no block at all is still a pause: the transfer stopped because they asked, the next attempt
            // starts this file from its beginning, and the hash at the end is unchanged either way.
            let block = waiter.pauseBlock ?? carried ?? Data()
            resolve(token, with: .paused(resumeData: block))
            return
        }
        // A cancellation is not a failure when the system hands back a resume block: the bytes
        // already transferred stay on disk and the transfer continues from them.
        if nsError.code == NSURLErrorCancelled, let carried {
            resolve(token, with: .paused(resumeData: carried))
            return
        }
        resolve(token, with: .failed(message: NetworkFault.message(for: nsError)))
    }

    private func update<R>(_ token: Int, _ change: (inout Waiter) -> R) -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard var waiter = waiters[token], !waiter.finished else { return nil }
        let result = change(&waiter)
        waiters[token] = waiter
        return result
    }

    private func read(_ token: Int) -> Waiter? {
        lock.lock()
        defer { lock.unlock() }
        return waiters[token]
    }

    /// Gives one transfer exactly one answer, and keeps it if nobody has asked for it yet.
    ///
    /// The finished flag is flipped here and nowhere else, because a transfer that is answered twice resumes a
    /// continuation twice — which is not a wrong number but a crash. Whether the answer can be delivered or has
    /// to be filed is the only branch, and the entry leaves the table as soon as it has been delivered: an
    /// answered waiter has nothing left to report, and a forty-file repository that carries its forty answers
    /// around for the rest of the app's life is a leak with a name.
    private func resolve(_ token: Int, with outcome: ModelDownloadOutcome) {
        let resumed: CheckedContinuation<ModelDownloadOutcome, Never>?
        lock.lock()
        if var waiter = waiters[token], !waiter.finished {
            waiter.finished = true
            resumed = waiter.continuation
            waiter.continuation = nil
            if resumed == nil {
                waiter.pendingOutcome = outcome
                waiters[token] = waiter
            } else {
                waiters.removeValue(forKey: token)
            }
        } else {
            resumed = nil
        }
        lock.unlock()
        resumed?.resume(returning: outcome)
    }

    func token(for task: URLSessionTask) -> Int? {
        task.taskDescription.flatMap { Int($0) }
    }
}
