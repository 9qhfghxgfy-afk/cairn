import Foundation

/// Routes URLSession download delegate callbacks back to the call that started the task.
///
/// The token travels on `taskDescription`, so a callback always finds the waiter that started its
/// own task even when several files are in flight. State is guarded by a lock rather than an actor
/// because the delegate callbacks are synchronous and their ordering matters: a progress callback
/// that lands after its task finished must not be re-sequenced behind it.
///
/// Only byte counts and tokens are ever touched here — no URL, no query string, no file contents.
final class DownloadBridge: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Why this process asked for a transfer to stop, as distinct from a route dropping or the surrounding
    /// task being cancelled. The two are worth different things: a pause wants the resume block the system
    /// produces, a cancel wants nothing kept.
    enum StopMode: Sendable, Equatable { case pause, cancel }

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
        /// nil until something in this app presses Pause or Cancel on this file. A stop that came from
        /// anywhere else keeps the older behaviour, which is to hand back a resume block whenever the
        /// system offers one.
        var stopMode: StopMode?
        /// The resume block a pause's cancellation handed back, filed here until the guaranteed completion
        /// callback is ready to answer with it. See `recordPauseBlock`.
        var pauseBlock: Data?
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
        mutate(token) { $0.task = task }
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
    /// completion handler, the matching error comes on `didCompleteWithError`. Answering from whichever got
    /// there first is how four gigabytes get thrown away by a race nobody can see — the one that arrives
    /// first may be the one carrying nothing. So this stores, and `didCompleteWithError` answers, because
    /// that callback is documented always to come. It takes the best block it can see: the one filed here if
    /// it has landed, else the one on its own error, else nothing, which means the next attempt starts this
    /// file over and still hashes it at the end.
    private func recordPauseBlock(token: Int, resumeData: Data?) {
        guard let resumeData, !resumeData.isEmpty else { return }
        mutate(token) { waiter in
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

    func wait(for token: Int) async -> ModelDownloadOutcome {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if var waiter = waiters[token], !waiter.finished {
                    waiter.continuation = continuation
                    waiters[token] = waiter
                    lock.unlock()
                } else {
                    lock.unlock()
                    continuation.resume(returning: .failed(message: "The download was cancelled."))
                }
            }
        } onCancel: {
            // Cancelling the URLSession task is what yields a resume block, so a cancelled download
            // can be picked up again instead of starting from the beginning.
            cancel(token)
        }
    }

    private func mutate(_ token: Int, _ change: (inout Waiter) -> Void) {
        lock.lock()
        if var waiter = waiters[token], !waiter.finished {
            change(&waiter)
            waiters[token] = waiter
        }
        lock.unlock()
    }

    private func read(_ token: Int) -> Waiter? {
        lock.lock()
        defer { lock.unlock() }
        return waiters[token]
    }

    private func resolve(_ token: Int, with outcome: ModelDownloadOutcome) {
        var resumed: CheckedContinuation<ModelDownloadOutcome, Never>?
        lock.lock()
        if var waiter = waiters[token], !waiter.finished {
            waiter.finished = true
            resumed = waiter.continuation
            waiter.continuation = nil
            waiters[token] = waiter
        }
        lock.unlock()
        resumed?.resume(returning: outcome)
    }

    private func token(for task: URLSessionTask) -> Int? {
        task.taskDescription.flatMap { Int($0) }
    }
}

extension DownloadBridge {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let token = token(for: downloadTask), let onProgress = read(token)?.onProgress else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        // Recorded before it is sent, so a later waiting update repeats the highest number this task has
        // reached instead of whatever its own counter happens to say at that moment.
        mutate(token) { if totalBytesWritten > $0.reportedBytes { $0.reportedBytes = totalBytesWritten } }
        onProgress(DownloadProgressUpdate(receivedBytes: totalBytesWritten, expectedBytes: expected))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let token = token(for: downloadTask), let target = read(token)?.destination else { return }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            resolve(token, with: .failed(message: "The downloaded file could not be stored."))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let token = token(for: task) else { return }
        guard let error else {
            var written: Int64 = 0
            if let target = read(token)?.destination {
                let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
                written = (attributes?[.size] as? Int64) ?? 0
            }
            resolve(token, with: .complete(bytes: written))
            return
        }

        let nsError = error as NSError
        let carried = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if nsError.code == NSURLErrorCancelled, read(token)?.stopMode == .cancel {
            // Given up on, so nothing that came out of this connection is kept — above all not the resume
            // block, which would let a later attempt carry on from bytes whose verification record has been
            // forgotten. The caller clears the file; this decides that the block never gets written.
            resolve(token, with: .cancelled)
            return
        }
        if nsError.code == NSURLErrorCancelled, read(token)?.stopMode == .pause {
            // The pause the person asked for, answered from the one callback a pause is documented always to
            // produce. A block filed from the other callback outranks the one on this error, and a pause with
            // no block at all is still a pause: the transfer stopped because they asked, the next attempt
            // starts this file from its beginning, and the hash at the end is unchanged either way.
            let block = read(token)?.pauseBlock ?? carried ?? Data()
            resolve(token, with: .paused(resumeData: block))
            return
        }
        // A cancellation is not a failure when the system hands back a resume block: the bytes
        // already transferred stay on disk and the transfer continues from them.
        if nsError.code == NSURLErrorCancelled, let resumeData = carried {
            resolve(token, with: .paused(resumeData: resumeData))
            return
        }
        resolve(token, with: .failed(message: "The download failed."))
    }

    /// The system parked a task instead of failing it: `waitsForConnectivity` is on, so a route that is
    /// down is retried and the task stays open rather than dying with an error nobody can act on.
    ///
    /// Without this callback the only sign of that state is a bar that stops moving, which is the single
    /// most misread thing on a phone pulling several gigabytes — the person assumes the app hung and
    /// Without this callback the only sign of that state is a bar that stops moving, which is the single
    /// most misread thing on a phone pulling several gigabytes — the person assumes the app hung and
    /// kills a transfer that was going to carry on by itself. This is the only spelling the protocol
    /// carries, and it is worth saying so: a method whose signature does not match an optional requirement
    /// compiles, never runs, and reports nothing, so a second guess at the same verb would have looked
    /// like coverage and been a silent hole.
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        reportWaiting(for: task)
    }

    private func reportWaiting(for task: URLSessionTask) {
        guard let token = token(for: task), let waiter = read(token), !waiter.finished else { return }
        let expected = task.countOfBytesExpectedToWrite > 0 ? task.countOfBytesExpectedToWrite : nil
        waiter.onProgress(
            DownloadProgressUpdate(
                receivedBytes: waiter.reportedBytes,
                expectedBytes: expected,
                isWaiting: true
            )
        )
    }

    /// A redirect is a new request, and it is not automatically the same server.
    ///
    /// The Hub answers a weight download by pointing somewhere else — a storage host the person never
    /// named and never authorised. A bearer token is proof of who asked, so it stops at the host it was
    /// written for; the redirect's own signed URL is what authorises the storage host, and it needs
    /// nothing else. Dropping the header is done by name rather than by rebuilding the request, so every
    /// other header the redirect needed (range, accept, content length) still arrives intact — losing one
    /// of those is how a resumed download silently restarts from zero.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var onward = request
        if !HuggingFaceEndpoints.mayCarryCredential(from: task.currentRequest?.url, to: request.url) {
            for field in ["Authorization", "X-API-Key", "Api-Key", "Cookie"] {
                onward.setValue(nil, forHTTPHeaderField: field)
            }
        }
        completionHandler(onward)
    }
}
