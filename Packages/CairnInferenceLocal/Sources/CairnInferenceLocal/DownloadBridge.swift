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
    private struct Waiter {
        let destination: URL
        let onProgress: @Sendable (DownloadProgressUpdate) -> Void
        var task: URLSessionTask?
        var continuation: CheckedContinuation<ModelDownloadOutcome, Never>?
        var finished = false
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

    func attach(_ token: Int, task: URLSessionTask) {
        mutate(token) { $0.task = task }
    }

    func cancel(_ token: Int) {
        lock.lock()
        let task = waiters[token]?.task
        lock.unlock()
        task?.cancel()
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
        // A cancellation is not a failure when the system hands back a resume block: the bytes
        // already transferred stay on disk and the transfer continues from them.
        if nsError.code == NSURLErrorCancelled,
           let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resolve(token, with: .paused(resumeData: resumeData))
            return
        }
        resolve(token, with: .failed(message: "The download failed."))
    }
}
