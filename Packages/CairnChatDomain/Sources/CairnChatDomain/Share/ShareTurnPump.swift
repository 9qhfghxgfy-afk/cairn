import Foundation

/// Where a shared turn's bytes go. One method per thing a socket can be asked to do, so the pump
/// that turns a model stream into a wire stream is testable with a recorder instead of a listener.
public protocol ShareFrameWriting: AnyObject, Sendable {
    /// The response head, written once, before any body byte.
    func writeHead(_ reply: ShareReply) async
    /// One body piece. For a stream this is one frame and it is flushed now, not buffered.
    func writeFrame(_ frame: String) async
    /// Half-close the write side: the answer is over, and for a stream the end of the socket is what
    /// tells a client that, because a streamed response carries no Content-Length.
    func finishWriting() async
}

/// Runs one turn for one client and writes its answer.
///
/// Three rules worth stating because they are the ones a careless server gets wrong:
/// - the head goes out **before** the first token, so a client switches to streaming mode instead of
///   waiting for a body length that is never coming;
/// - a failure mid-stream is written as the dialect's own error shape rather than as a truncated
///   answer, so a client sees a stated failure instead of a model that apparently stopped early;
/// - the reason a turn ended comes from what actually happened — finished, cancelled, or failed —
///   because a client is entitled to know whether the answer it got was the whole one.
public enum ShareTurnPump {
    /// The words a client sees when the engine failed. Typed and short: nothing the model said,
    /// nothing the user asked, and no address or key can ride along in it.
    public static let failureText = "the model could not answer"

    @discardableResult
    public static func run(
        turn: ShareTurnRequest,
        provider: any InferenceProvider,
        to sink: any ShareFrameWriting
    ) async -> FinishReason {
        var encoder = ShareStreamEncoder(shape: ShareStreamShape.forEndpoint(turn.endpoint) ?? .ollamaChat, model: turn.modelID)
        do {
            if turn.streams {
                await sink.writeHead(encoder.streamReply)
            }
            for try await chunk in provider.stream(turn.generationRequest()) {
                let frames = encoder.append(chunk)
                // A whole-answer turn still reads the stream, because that is what an engine offers;
                // it simply does not forward the pieces, since they go out once, assembled, at the end.
                if turn.streams {
                    for frame in frames { await sink.writeFrame(frame) }
                }
            }
            return await conclude(turn: turn, encoder: encoder, reason: .stop, to: sink)
        } catch is CancellationError {
            return await conclude(turn: turn, encoder: encoder, reason: .cancelled, to: sink)
        } catch {
            return await conclude(turn: turn, encoder: encoder, reason: .error, to: sink)
        }
    }

    /// The last bytes of an answer, in whichever shape the client is reading.
    private static func conclude(
        turn: ShareTurnRequest,
        encoder: ShareStreamEncoder,
        reason: FinishReason,
        to sink: any ShareFrameWriting
    ) async -> FinishReason {
        if !turn.streams {
            if reason == .error {
                await sink.writeHead(ShareHTTPResponse.error(status: 500, dialect: encoder.shape.dialect, message: failureText))
            } else {
                await sink.writeHead(encoder.bufferedReply())
            }
            await sink.finishWriting()
            return reason
        }
        if reason == .error {
            for frame in errorFrames(dialect: encoder.shape.dialect) {
                await sink.writeFrame(frame)
            }
        } else {
            var closing = encoder
            for frame in closing.finish(reason: reason) {
                await sink.writeFrame(frame)
            }
        }
        await sink.finishWriting()
        return reason
    }

    static func errorFrames(dialect: ShareDialect) -> [String] {
        switch dialect {
        case .ollama: return [ShareFrame.ndjson(ShareErrorBody.ollama(failureText))]
        // The error event and the sentinel are separate frames so a client reads a stated failure and
        // then a stated end, in that order, rather than one write it has to split apart.
        case .openAI: return [ShareFrame.sse(ShareErrorBody.openAI(failureText, kind: "server_error")), ShareFrame.sseDone]
        }
    }
}
