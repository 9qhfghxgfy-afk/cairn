import CairnChatDomain
import Foundation

/// The landing point for tokens the on-device runtime emits.
///
/// The runtime calls back from its own thread, so the template parser cannot simply be a local the
/// callback closes over: two chunks must not be ingested at once, and the chunks handed to the caller must
/// stay in the order they arrived. Everything goes through here under one lock.
///
/// `.content` is the only kind that passes through the template parser, because it is the only kind that
/// can carry a think-block or tool-block marker. Thinking, tool calls and metrics arrive already in
/// Cairn's vocabulary and are forwarded untouched — a value the runtime measured is not something this
/// bridge may re-derive.
final class MLXStreamBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: DeviceTemplateChunkParser
    private var continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    private var cancelled = false
    private var sawFirstContent = false
    private var onFirstContent: (@Sendable () -> Void)?

    /// `onFirstContent` lets the provider mark the model resident at the moment it starts answering,
    /// which is the earliest point at which saying "this model is in memory" is true.
    init(
        parser: DeviceTemplateChunkParser,
        continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation,
        onFirstContent: (@Sendable () -> Void)? = nil
    ) {
        self.parser = parser
        self.continuation = continuation
        self.onFirstContent = onFirstContent
    }


    func receive(_ chunk: StreamChunk) {
        lock.lock()
        if cancelled {
            lock.unlock()
            return
        }
        var settled: [StreamChunk] = []
        switch chunk {
        case .content(let text):
            if !sawFirstContent {
                sawFirstContent = true
                let mark = onFirstContent
                settled = parser.ingest(text)
                lock.unlock()
                mark?()
            } else {
                settled = parser.ingest(text)
                lock.unlock()
            }
        default:
            lock.unlock()
            settled = [chunk]
        }
        for piece in settled { continuation.yield(piece) }
    }

    /// Ends the turn: whatever the parser was still holding is released, then the stream is finished.
    func complete() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        let settled = parser.finish()
        lock.unlock()
        for piece in settled { continuation.yield(piece) }
        continuation.finish()
    }

    /// A cancelled turn drops the buffered tail rather than emitting it: the partial answer already sent
    /// stands, and a half-word released after a stop reads as if the model finished speaking.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
