import Foundation

/// File transfer with genuine pause and resume.
///
/// An ephemeral configuration is used deliberately: no shared cache that could keep a model's bytes
/// somewhere the storage-cleanup path does not look. Resume works through the resume block the
/// system produces when a task is cancelled, which is what lets a multi-gigabyte download survive a
/// dropped Wi-Fi connection without starting over.
///
/// Extended background idle mode keeps a transfer alive briefly when the app is backgrounded. It is
/// not a compute strategy and it is not a substitute for the background-task work in Milestone 5.
public final class URLSessionModelDownloader: ModelFileDownloading {
    private let bridge = DownloadBridge()
    private let session: URLSession

    public init(requestTimeout: TimeInterval = 60) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
    }

    public func fetch(
        _ file: ModelFileDescriptor,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        await run(session.downloadTask(with: file.url), destination: destination, onProgress: onProgress)
    }

    public func resume(
        using resumeData: Data,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        // Not optional on this SDK: an unusable resume block surfaces as a failed transfer, which
        // the caller reports as "the pause could not be picked up again".
        let task = session.downloadTask(withResumeData: resumeData)
        return await run(task, destination: destination, onProgress: onProgress)
    }

    private func run(
        _ task: URLSessionDownloadTask,
        destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        let token = bridge.register(destination: destination, onProgress: onProgress)
        task.taskDescription = String(token)
        bridge.attach(token, task: task)
        task.resume()
        return await bridge.wait(for: token)
    }
}
