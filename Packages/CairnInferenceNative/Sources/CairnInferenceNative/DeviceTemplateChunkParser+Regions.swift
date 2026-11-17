import CairnChatDomain
import Foundation

/// Region bookkeeping for `DeviceTemplateChunkParser`, kept apart from its public surface so
/// each file stays small and single-purpose.
extension DeviceTemplateChunkParser {
    /// The earliest marker in `text`, so regions cannot be entered out of the order the model
    /// actually wrote them in.
    func earliest(in text: String) -> (marker: DeviceTemplateMarker, range: Range<String.Index>)? {
        var best: (marker: DeviceTemplateMarker, range: Range<String.Index>)?
        for marker in DeviceTemplateMarker.allCases {
            guard let found = text.range(of: marker.text) else { continue }
            if let current = best {
                if found.lowerBound < current.range.lowerBound { best = (marker, found) }
            } else {
                best = (marker, found)
            }
        }
        return best
    }

    mutating func apply(match marker: DeviceTemplateMarker, to out: inout [StreamChunk]) {
        if marker.opensRegion {
            region = marker
            return
        }
        let opener: DeviceTemplateMarker =
            (marker == .thinkingClose) ? .thinkingOpen : .toolStart
        let body = take(opener) ?? ""
        region = nil

        if marker == .thinkingClose {
            // An empty thinking region is reported as nothing at all. A panel reading "no
            // reasoning" is worse than no panel.
            if !body.isEmpty { out.append(.thinking(body)) }
        } else if let call = ToolCallCodec.decode(body) {
            out.append(.toolCall(call))
        } else if unterminatedToolRegionBecomesContent, !body.isEmpty {
            out.append(contentsOf: flush(body))
        }
    }

    mutating func take(_ marker: DeviceTemplateMarker?) -> String? {
        guard let marker else { return nil }
        let text = regionText[marker]
        regionText[marker] = nil
        return text
    }

    mutating func flush(_ text: String) -> [StreamChunk] {
        var body = text
        if trimsLeadingWhitespace, !emittedAnyContent {
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return [] }
        emittedAnyContent = true
        return [.content(body)]
    }

    /// The longest suffix of `text` that could still grow into a marker. Held back so a marker
    /// split across two streamed pieces is still recognised; released as content when the next
    /// chunk shows it was never one.
    func holdBackAmbiguousTail(of text: String) -> String {
        guard !text.isEmpty else { return "" }
        let scalars = Array(text.unicodeScalars)
        let longest = DeviceTemplateMarker.allCases.map { $0.text.count }.max() ?? 0
        for length in stride(from: min(scalars.count, longest), through: 1, by: -1) {
            let candidate = String(String.UnicodeScalarView(scalars.suffix(length)))
            let couldGrow = DeviceTemplateMarker.allCases.contains { marker in
                marker.text.hasPrefix(candidate) && marker.text != candidate
            }
            if couldGrow { return candidate }
        }
        return ""
    }
}
