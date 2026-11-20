import Foundation

/// The URLSession callbacks, kept as thin adapters over the rules held in `DownloadBridge`.
///
/// Nothing here decides anything: it reads a task, hands the numbers to the bridge, and calls the completion
/// handler the protocol asks for. That split is what makes a download testable — the rules can be driven
/// directly with a token and a synthetic response, while these methods only have to be shaped exactly right.
///
/// The shape matters more than it looks. A delegate method whose signature does not match an optional protocol
/// requirement compiles, never runs, and reports nothing at all, so a second guess at the same verb reads as
/// coverage and is a silent hole. And the conformance has to be declared on the class, not inferred from these
/// method names — see the note on the declaration in `DownloadBridge.swift`, which is what a stalled four
/// gigabyte file on an iPhone taught about that one.
extension DownloadBridge {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let token = token(for: downloadTask) else { return }
        emitProgress(token: token, received: totalBytesWritten,
                     expectedFromServer: totalBytesExpectedToWrite)
    }

    /// The handoff: the system's temporary file becomes the file in the store — if the answer is a file.
    ///
    /// The status is checked inside `storeFile` before anything moves, because a download task reports a 401,
    /// 403, 404 or 429 as a finished transfer carrying the server's error page.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let token = token(for: downloadTask) else { return }
        storeFile(location, for: token, response: downloadTask.response)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let token = token(for: task) else { return }
        answer(token: token, failure: error)
    }

    /// The system parked a task instead of failing it: `waitsForConnectivity` is on, so a route that is
    /// down is retried and the task stays open rather than dying with an error nobody can act on.
    ///
    /// Without this callback the only sign of that state is a bar that stops moving, which is the single
    /// most misread thing on a phone pulling several gigabytes — the person assumes the app hung and kills a
    /// transfer that was going to carry on by itself. This is the only spelling the protocol carries, and it is
    /// worth saying so: a method whose signature does not match an optional requirement compiles, never runs,
    /// and reports nothing, so a second guess at the same verb would have looked like coverage and been a
    /// silent hole.
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let token = token(for: task) else { return }
        // A download receives bytes; there is no "expected to write" on a task. Naming the wrong pair here
        // would have compiled against nothing at all, so the ceiling this reports is the one the server
        // actually declared in Content-Length.
        emitWaiting(token: token, expectedFromServer: task.countOfBytesExpectedToReceive)
    }

    /// A redirect is a new request, and it is not automatically the same server.
    ///
    /// The Hub answers a weight download by pointing somewhere else: measured against the real endpoint on
    /// 2026-11-20, `model.safetensors` answers 302 to a signed address on a storage host (`cas-bridge.xethub`
    /// and `cdn-lfs*` are older spellings of the same hop), while a small `config.json` answers 307 to a cache
    /// address on the Hub's own host. A bearer token is proof of who asked, so it stops at the host it was
    /// written for; the redirect's own signed query is what authorises the storage host and it needs nothing
    /// else — that host serves the bytes with no credential at all, which is also how a resumed `Range` header
    /// survives the hop intact.
    ///
    /// Dropping the header is done by name rather than by rebuilding the request, so every other header the
    /// redirect needs — range, accept, user agent — still arrives. Losing one of those is how a resumed
    /// download silently restarts from zero. The completion handler is always called: not answering it, or
    /// answering with nil, parks a task rather than failing it, and a parked task is a bar that stops moving.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // The address that produced this redirect is the one on the response, and it is always filled in.
        // `task.currentRequest` is the weaker source of the two: it names whatever the task last sent, and a
        // nil there would drop a credential on a same-host hop and break an authenticated download of a
        // repository that needs one.
        let source = response.url ?? task.currentRequest?.url
        completionHandler(Self.redirectRequest(request, redirectedFrom: source))
    }

    /// The request to send onward after a redirect, with the credential settled.
    ///
    /// Pure, and that is why the rule is testable: a request goes in, a request comes out, and no session,
    /// socket or simulator is involved. A same-host hop keeps the credential — an authenticated retry of the
    /// host the token was written for still has to work — and a cross-host hop loses it.
    static func redirectRequest(_ request: URLRequest, redirectedFrom source: URL?) -> URLRequest {
        var onward = request
        guard !HuggingFaceEndpoints.mayCarryCredential(from: source, to: request.url) else { return onward }
        for field in ["Authorization", "X-API-Key", "Api-Key", "Cookie"] {
            onward.setValue(nil, forHTTPHeaderField: field)
        }
        return onward
    }
}
