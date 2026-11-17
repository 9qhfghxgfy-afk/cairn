import CairnChatDomain
import Foundation

/// Streams a whole turn through the parser and collects the result, for replay, export, and
/// tests that assert the final shape of an answer rather than its chunk boundaries.
///
/// The chunk boundaries a model happens to stream in are not a property of the answer, so the
/// same text must produce the same result however it arrived. That is what this type proves.
public struct DeviceTemplateChunkAccumulator {
    private var parser = DeviceTemplateChunkParser()
    private var pieces: [String] = []
    private var thinkingParts: [String] = []
    private var calls: [ToolCallRequest] = []

    public init() {}

    public mutating func consume(_ token: String) {
        pieces.append(token)
        settle(parser.ingest(token))
    }

    public mutating func complete() {
        settle(parser.finish())
    }

    mutating func settle(_ chunks: [StreamChunk]) {
        for chunk in chunks {
            switch chunk {
            case .content(let piece): body += piece
            case .thinking(let piece): thinkingParts.append(piece)
            case .toolCall(let call): calls.append(call)
            case .metrics: break
            }
        }
    }

    /// Body text with every thinking region removed — what a transcript shows.
    public var content: String { body }
    /// Joined only when at least one region really arrived, so an absent thinking field stays
    /// absent rather than becoming an empty panel.
    public var thinking: String? { thinkingParts.isEmpty ? nil : thinkingParts.joined() }
    public var toolCalls: [ToolCallRequest] { calls }
    public var sawThinkingRegion: Bool { !thinkingParts.isEmpty }

    private var body = ""
}

public extension DeviceTemplateChunkAccumulator {
    /// Runs the whole string in one pass.
    static func parse(_ text: String) -> DeviceTemplateChunkAccumulator {
        var accumulator = DeviceTemplateChunkAccumulator()
        accumulator.consume(text)
        accumulator.complete()
        return accumulator
    }

    /// Runs the same text as if it had arrived piecewise, including splits through a marker.
    static func parse(pieces: [String]) -> DeviceTemplateChunkAccumulator {
        var accumulator = DeviceTemplateChunkAccumulator()
        for piece in pieces { accumulator.consume(piece) }
        accumulator.complete()
        return accumulator
    }
}
