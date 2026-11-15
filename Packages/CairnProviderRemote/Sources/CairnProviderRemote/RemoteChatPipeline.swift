import Foundation
import CairnChatDomain

/// Drives one chat stream: bytes -> complete lines -> wire events -> `StreamChunk`, then the
/// measured metrics.
///
/// Framing goes through `LineStreamParser`, so a chunk that splits a line in half or lands
/// inside a multibyte character still decodes. Cancellation is explicit: the surrounding task
/// is cancelled, `abandon()` closes the producer, the blocked read wakes and throws, and the
/// pipeline re-throws `CancellationError` - which is what the session records as a stopped
/// turn rather than a failure.
enum RemoteChatPipeline {
    static func run(
        _ request: URLRequest,
        transport: any RemoteTransport,
        wire: any RemoteWire,
        continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    ) async throws {
        let opened = transport.open(request)
        do {
            try await withTaskCancellationHandler {
                try await consume(opened, wire: wire, continuation: continuation)
            } onCancel: {
                opened.abandon()
            }
        } catch {
            let mapped = RemoteError.classify(error)
            if Task.isCancelled || mapped == .cancelled { throw CancellationError() }
            throw mapped
        }
    }

    private static func consume(
        _ opened: RemoteByteStream,
        wire: any RemoteWire,
        continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    ) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        var parser = LineStreamParser()
        var sawContent = false
        var firstContentSeconds: Double?
        var finishReason: FinishReason = .unknown
        var promptTokens: Int?
        var completionTokens: Int?

        func handle(_ event: RemoteEvent) throws {
            switch event {
            case .thinking(let text):
                continuation.yield(.thinking(text))
            case .content(let text):
                if !sawContent {
                    sawContent = true
                    firstContentSeconds = elapsed(from: started, to: clock.now)
                }
                continuation.yield(.content(text))
            case .usage(let prompt, let completion):
                if let prompt { promptTokens = prompt }
                if let completion { completionTokens = completion }
            case .finished(let reason):
                finishReason = reason
            case .streamDone:
                break
            case .error(let message):
                throw RemoteError.serverMessage(message)
            }
        }

        for try await chunk in opened.bytes {
            if Task.isCancelled { throw CancellationError() }
            for line in parser.feed(chunk) {
                for event in try wire.decodeLine(line) { try handle(event) }
            }
        }

        // A stream that ends without a trailing newline still holds one complete event.
        if let tail = parser.takeTrailingPartialLine(), !tail.isEmpty {
            for event in try wire.decodeLine(tail + [0x0A]) { try handle(event) }
        }

        if let metrics = RemoteMetrics.make(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            elapsedSeconds: elapsed(from: started, to: clock.now),
            timeToFirstTokenSeconds: firstContentSeconds,
            finishReason: finishReason
        ) {
            continuation.yield(.metrics(metrics))
        }
    }

    /// Monotonic clock only: a wall-clock jump must never distort a measured latency.
    static func elapsed(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: end).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
