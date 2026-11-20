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
///
/// Two settings decide whether a five-gigabyte file lands, and both are easy to get wrong:
///
/// - `timeoutIntervalForRequest` is the gap **between bytes**, not the length allowed for the whole
///   transfer, so 60 seconds of silence is what kills a stalled socket instead of leaving a task open
///   with nothing coming through it. The total allowance is `timeoutIntervalForResource`, set to six
///   hours: a large quantised model on a phone's Wi-Fi is measured in hours, and a resource timeout
///   tuned for an API call fails the transfer at the point where most of it has already been paid for.
/// - `waitsForConnectivity` makes a dropped route a wait rather than a failure. The bridge reports that
///   state so the screen can say "Waiting for the network" instead of leaving a bar parked with no
///   explanation.
public final class URLSessionModelDownloader: ModelFileDownloading {
    /// Seconds without a single byte before a task is given up on.
    ///
    /// Public because the initializer's default argument names it, and a public default may only name a
    /// public symbol — the value is the documented ceiling, not an internal detail worth hiding.
    public static let defaultRequestTimeout: TimeInterval = 60
    /// The whole transfer's ceiling, measured from the moment the task starts.
    static let resourceTimeout: TimeInterval = 60 * 60 * 6

    private let bridge = DownloadBridge()
    private let session: URLSession
    /// The optional Hub credential, read at the moment a request is built rather than copied at launch.
    ///
    /// A token pasted in Settings has to reach the next file, and a token deleted there has to stop
    /// reaching it; a value read once at startup does neither, and a person who removes their credential
    /// is owed a download that really stopped using it. The closure is the same shape the outbound
    /// acknowledgement uses, and for the same reason.
    private let credential: @Sendable () -> String?

    public init(
        requestTimeout: TimeInterval = URLSessionModelDownloader.defaultRequestTimeout,
        credential: @Sendable @escaping () -> String? = { nil }
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.waitsForConnectivity = true
        // No cookie jar, and nothing shared: a model's bytes and a credential belong to one app run and
        // to the Keychain, not to a session cache the storage-cleanup path never walks.
        configuration.httpShouldSetCookies = false
        self.credential = credential
        self.session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
    }

    public func fetch(
        _ file: ModelFileDescriptor,
        to destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressUpdate) -> Void
    ) async -> ModelDownloadOutcome {
        // The task is created here, not inside `run`, because both entry points differ exactly at this
        // line: a fresh file is a task built from a request, a resumed one is a task built from the block
        // a pause produced. Everything after it — registration, the description the delegate reads, the
        // wait — is the same for both.
        let task = session.downloadTask(with: request(for: file.url))
        return await run(task, destination: destination, onProgress: onProgress)
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

    /// Closes the connections of one repository's files, now rather than at the next gap between bytes.
    ///
    /// The two verbs are two methods, not one method with a flag: `cancel(byProducingResumeData:)` asks for
    /// the block a later resume is built from, and plain `cancel()` asks for nothing. That difference is the
    /// whole reason this method exists — a Pause that asks for nothing is a Download button with an extra tap,
    /// and a Cancel that asks for a block leaves a resume pointing at bytes this app is about to delete. Both
    /// close the socket at once, so a Pause pressed during a four-gigabyte file stops that file rather than
    /// the next one.
    ///
    /// What cannot be settled from the machine writing this: whether a block from a non-background session
    /// still resumes after this app has been quit and reopened, since the temporary file it points into is
    /// the system's to reclaim. If it does not survive, a resume starts that file over and hashes it at the
    /// end — slower, and honest, because the numbers shown are the ones actually on disk either way. That is
    /// an on-device check, recorded as one, not a claim.
    public func stopTransfers(in directory: URL, pause: Bool) -> Int {
        bridge.stopTransfers(in: directory, pause: pause)
    }

    /// The request for one file: the fixed identity every Cairn request carries, plus the bearer only
    /// when this phone was given one.
    ///
    /// The header goes on the request rather than into `httpAdditionalHeaders` on purpose. Session-level
    /// headers are re-applied to every hop of a redirect, so a credential put there would ride along to
    /// the storage host the Hub hands out; on the request, the bridge's redirect handler can take it off
    /// at the host boundary.
    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let headers = HuggingFaceEndpoints.authorizedHeaders(token: credential())
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
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
