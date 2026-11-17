import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

/// Tags are built by concatenation everywhere, including here. A literal tag in a source file
/// collides with the reasoning control token of the toolchain that reads this code.
private let openThink = "<" + "think" + ">"
private let closeThink = "</" + "think" + ">"
private let openTool = "<tool_call>"
private let closeTool = "</tool_call>"

struct DeviceTemplateChunkParserTests {
    @Test func plainTextIsContentWithNoThinkingChunk() {
        var parser = DeviceTemplateChunkParser()
        let out = parser.ingest("Just an answer.")
        #expect(out == [.content("Just an answer.")])
    }

    @Test func thinkingRegionBecomesOneThinkingChunk() {
        let text = "\(openThink)weighing options\(closeThink)the answer"
        let parsed = DeviceTemplateChunkAccumulator.parse(text)
        #expect(parsed.thinking == "weighing options")
        #expect(parsed.content == "the answer")
        #expect(parsed.sawThinkingRegion)
    }

    @Test func noMarkersMeansNoThinkingAndNoToolCall() {
        // The rule that matters: an absent thinking field never becomes an empty reasoning panel.
        let parsed = DeviceTemplateChunkAccumulator.parse("no markers at all")
        #expect(parsed.thinking == nil)
        #expect(parsed.toolCalls.isEmpty)
        #expect(parsed.content == "no markers at all")
    }

    @Test func markerSplitAcrossChunksIsStillRecognised() {
        let parsed = DeviceTemplateChunkAccumulator.parse(pieces: [
            "before", openThink, "reason", closeThink, "after",
        ])
        #expect(parsed.thinking == "reason")
        #expect(parsed.content == "beforeafter")
    }

    @Test func sameResultHoweverTheStreamWasChopped() {
        let whole = "\(openThink)deep\(closeThink)body text"
        let chopped = DeviceTemplateChunkAccumulator.parse(
            pieces: ["<", "th", "ink>", "dee", "p", "</th", "ink>", "body text"]
        )
        let single = DeviceTemplateChunkAccumulator.parse(whole)
        #expect(chopped.content == single.content)
        #expect(chopped.thinking == single.thinking)
    }

    @Test func unterminatedThinkingIsStillReported() {
        // A stream cut off mid-reasoning must not lose what the model did emit.
        let parsed = DeviceTemplateChunkAccumulator.parse("\(openThink)half a thought")
        #expect(parsed.thinking == "half a thought")
    }

    @Test func toolCallJSONRegionBecomesOneToolCallChunk() {
        let body = #"{"name":"search","arguments":{"query":"weather"}}"#
        var parser = DeviceTemplateChunkParser()
        var chunks = parser.ingest("\(openTool)\(body)\(closeTool)")
        chunks += parser.finish()
        let calls = chunks.compactMap { chunk in
            if case .toolCall(let call) = chunk { return call } else { return nil }
        }
        #expect(calls.count == 1)
        #expect(calls.first?.name == "search")
        #expect(calls.first?.argumentsJSON.contains("weather") == true)
    }

    @Test func toolCallTagFormIsAlsoRead() {
        let parsed = DeviceTemplateChunkAccumulator.parse(
            "\(openTool)<function=lookup><parameter=city>Oslo</parameter></function>\(closeTool)"
        )
        #expect(parsed.toolCalls.first?.name == "lookup")
        #expect(parsed.toolCalls.first?.argumentsJSON.contains("Oslo") == true)
    }

    @Test func unparseableToolRegionFallsBackToContentRatherThanVanishing() {
        let parsed = DeviceTemplateChunkAccumulator.parse("\(openTool)not json at all")
        #expect(parsed.toolCalls.isEmpty)
        #expect(parsed.content.contains("not json at all"))
    }

    @Test func leadingWhitespaceIsTrimmedOnlyBeforeRealContent() {
        let parsed = DeviceTemplateChunkAccumulator.parse(pieces: ["\n", "first", " second"])
        #expect(parsed.content == "first second")
    }
}
