import Foundation
import CairnChatDomain

/// The streaming half of the lifecycle service: a model download that reports progress as it
/// arrives and can actually be stopped.
///
/// Cancellation here is real, not decorative. Cancelling a Swift task does not wake a consumer
/// blocked on a socket, so the byte stream is abandoned on every exit path — task cancellation,
/// the consumer stopping iteration, or an error. That is the difference between "Stop" closing the
/// connection and "Stop" leaving a 4 GB download running.
extension RemoteModelLifecycleService {
    public func pull(model: String, profile: ServerProfile) -> AsyncThrowingStream<ModelPullProgress, any Error> {
        let endpoints = profile.kind.backend.endpoints
        guard endpoints.lifecycleWired, endpoints.download != nil, supportsLifecycle(profile) else {
            return failingStream(ModelLifecycleError.unsupported(profile.kind))
        }
        guard profile.usableNow else {
            return failingStream(ModelLifecycleError.optInRequired)
        }

        // LM Studio's route answers once rather than streaming, so it is a single reported step.
        if profile.kind == .lmStudio { return requestedStream(model: model, profile: profile) }

        guard let path = endpoints.download,
              let request = RemoteRequests.make(
                  profile: profile, method: "POST", path: path,
                  body: try? OllamaLifecycleCodec.pullRequestBody(model: model),
                  accept: "application/x-ndjson",
                  bearer: secrets.secret(for: profile.id)
              )
        else { return failingStream(ModelLifecycleError.invalidURL) }

        let opened = transport.open(request)
        return AsyncThrowingStream { continuation in
            let work = Task { @MainActor in
                var parser = LineStreamParser()
                do {
                    for try await piece in opened.bytes {
                        if Task.isCancelled { break }
                        for line in parser.feed(piece) {
                            try settle(line, model: model, into: continuation)
                        }
                    }
                    if let tail = parser.takeTrailingPartialLine(), !tail.isEmpty {
                        try settle(tail, model: model, into: continuation)
                    }
                    opened.abandon()
                    continuation.finish()
                } catch {
                    opened.abandon()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                opened.abandon()
                work.cancel()
            }
        }
    }

    /// One NDJSON line. Ollama reports a failed pull with HTTP 200 and an in-band error, so the
    /// error is checked before the status text is shown as progress.
    func settle(
        _ line: Data,
        model: String,
        into continuation: AsyncThrowingStream<ModelPullProgress, any Error>.Continuation
    ) throws {
        let text = String(decoding: line, as: UTF8.self)
        if let failure = OllamaLifecycleCodec.inBandError(in: text) {
            throw ModelLifecycleError.serverMessage(failure)
        }
        if let progress = OllamaLifecycleCodec.decodeProgressLine(text, model: model) {
            continuation.yield(progress)
        }
    }

    func requestedStream(model: String, profile: ServerProfile) -> AsyncThrowingStream<ModelPullProgress, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task { @MainActor in
                do {
                    guard let path = profile.kind.backend.endpoints.download else {
                        throw ModelLifecycleError.unsupported(profile.kind)
                    }
                    let data = try await exchange(
                        profile, method: "POST", path: path,
                        body: try LMStudioLifecycleCodec.downloadRequestBody(repository: model),
                        accept: "application/json"
                    )
                    switch LMStudioLifecycleCodec.readAcceptance(data) {
                    case .accepted:
                        continuation.yield(ModelPullProgress(modelName: model, statusText: "requested"))
                        continuation.finish()
                    case .refused(let message):
                        continuation.finish(throwing: ModelLifecycleError.serverMessage(message))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// One request. The outbound opt-in is checked here, before the request is built, and the
    /// bearer token is attached by the builder from the Keychain — never from a stored field.
    func exchange(
        _ profile: ServerProfile,
        method: String,
        path: String,
        body: Data?,
        accept: String
    ) async throws -> Data {
        guard profile.usableNow else { throw ModelLifecycleError.optInRequired }
        guard let request = RemoteRequests.make(
            profile: profile, method: method, path: path, body: body,
            accept: accept, bearer: secrets.secret(for: profile.id)
        ) else { throw ModelLifecycleError.invalidURL }
        return try await transport.exchange(request)
    }

    func failingStream(_ error: ModelLifecycleError) -> AsyncThrowingStream<ModelPullProgress, any Error> {
        AsyncThrowingStream(ModelPullProgress.self) { $0.finish(throwing: error) }
    }
}
