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
        /// Fragments of streamed calls, stitched in arrival order and handed over whole.
        var stitcher = RemoteToolCallStitcher()

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
            case .toolCall(let call):
                // A dialect that hands over the complete arguments needs no stitching; the call is
                // already whole, so the loop can run it as soon as it sees it.
                continuation.yield(.toolCall(call))
            case .toolCallDelta(let index, let id, let name, let arguments):
                stitcher.feed(index: index, id: id, name: name, arguments: arguments)
            case .usage(let prompt, let completion):
                if let prompt { promptTokens = prompt }
                if let completion { completionTokens = completion }
            case .finished(let reason):
                finishReason = reason
                // The choice is over, so every fragment of its calls has arrived: this is the earliest
                // point at which a call can honestly be called complete.
                for call in stitcher.flush() { continuation.yield(.toolCall(call)) }
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

        // A server that closed the stream without ever naming a finish reason still owes its calls:
        // dropping a stitched call here would leave the model waiting for a result it was never given.
        for call in stitcher.flush() { continuation.yield(.toolCall(call)) }

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
