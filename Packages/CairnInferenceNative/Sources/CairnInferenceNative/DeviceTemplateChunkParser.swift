import CairnChatDomain
import Foundation

/// Turns one local model's flat token stream into Cairn's chunk vocabulary.
///
/// A local runtime hands the turn back as text, so the only honest way to show a reasoning panel
/// or a tool-call card for an on-device model is to read the markers its chat template actually
/// emitted. Text before any marker is ordinary `.content`. A thinking region becomes `.thinking`
/// only after its opening marker really arrived; a tool region is buffered and released as one
/// `.toolCall` at the close. A stream that emits no markers yields no thinking and no tool chunk,
/// which is the point: reasoning the model did not output is never shown as though it did.
///
/// Markers can straddle a chunk boundary, so an ambiguous tail is held back until the next chunk
/// decides whether it was a marker after all.
public struct DeviceTemplateChunkParser: Sendable {
    /// Whether this turn has tools the model was offered.
    ///
    /// A tool region naming one of them may be written in the flatter attribute form, which is only read
    /// when the name was really offered — so the parser carries the list rather than guessing at it. An
    /// empty list keeps the old, strict reading: JSON and function/parameter tags only.
    public var offeredTools: [ToolDefinition]
    /// Some templates prefix the turn with a newline. It is dropped, but only before anything
    /// real has been said, so a genuine leading newline later in an answer survives.
    public var trimsLeadingWhitespace: Bool
    /// A tool region with no close cannot be parsed into a call, and dropping it would hide
    /// something the model really emitted, so it surfaces as content instead.
    public var unterminatedToolRegionBecomesContent: Bool

    var region: DeviceTemplateMarker?
    var buffer = ""
    var emittedAnyContent = false
    var regionText: [DeviceTemplateMarker: String] = [:]

    public init(
        offeredTools: [ToolDefinition] = [],
        trimsLeadingWhitespace: Bool = true,
        unterminatedToolRegionBecomesContent: Bool = true
    ) {
        self.offeredTools = offeredTools
        self.trimsLeadingWhitespace = trimsLeadingWhitespace
        self.unterminatedToolRegionBecomesContent = unterminatedToolRegionBecomesContent
    }


    /// Feeds one streamed piece and returns the chunks it settles.
    public mutating func ingest(_ token: String) -> [StreamChunk] {
        var pending = buffer + token
        var settled = ""
        var out: [StreamChunk] = []

        while let match = earliest(in: pending) {
            let head = String(pending[..<match.range.lowerBound])
            pending = String(pending[match.range.upperBound...])
            if let region, region.opensRegion {
                // Text before a close marker belongs to the open region, not to the answer.
                regionText[region] = (regionText[region] ?? "") + head
            } else {
                settled += head
                out.append(contentsOf: flush(settled))
                settled = ""
            }
            apply(match: match.marker, to: &out)
        }

        let held = holdBackAmbiguousTail(of: pending)
        settled += String(pending.dropLast(held.count))
        buffer = held

        // Region bodies stay intact: a tool region is JSON and a thinking region is prose a
        // reader follows. Both are accumulated and released as one chunk when the region closes.
        if let region {
            regionText[region] = (regionText[region] ?? "") + settled
        } else {
            out.append(contentsOf: flush(settled))
        }
        return out
    }

    /// Ends the turn. A region the stream never closed is reported rather than lost, and an
    /// ambiguous tail that never resolved turns out to have been ordinary text.
    public mutating func finish() -> [StreamChunk] {
        var out: [StreamChunk] = []
        let tail = buffer
        buffer = ""

        if let region, region.opensRegion {
            let body = take(region) ?? ""
            if region == .thinkingOpen {
                if !body.isEmpty { out.append(.thinking(body)) }
            } else if unterminatedToolRegionBecomesContent, !body.isEmpty {
                out.append(contentsOf: flush(body))
            }
            self.region = nil
            out.append(contentsOf: flush(tail))
            return out
        }
        out.append(contentsOf: flush(tail))
        return out
    }
}
