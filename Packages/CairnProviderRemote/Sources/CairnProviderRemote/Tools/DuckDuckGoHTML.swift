import Foundation
import CairnChatDomain

/// Reading the keyless endpoint's result list out of its HTML.
///
/// **Best-effort, and labelled as such wherever it matters.** That endpoint publishes a page, not an
/// API; the markers below are the class names its result list uses today. If they change, the honest
/// answer is "no results" — which the tool returns as a typed failure the model can see, rather than a
/// page of markup dressed up as sources or a guess at what the page meant.
enum DuckDuckGoHTML {
    private static let anchorMarker = "result__a"
    private static let snippetMarker = "result__snippet"
    /// How far past a marker to look for its attributes, so one malformed page cannot make the scan
    /// walk a whole document.
    private static let attributeWindow = 400

    static func results(in html: String, limit: Int) -> [WebSearchResult] {
        var found: [WebSearchResult] = []
        var search = Substring(html)
        while found.count < max(1, limit), let mark = search.range(of: anchorMarker) {
            let tail = search[mark.upperBound...]
            search = tail
            guard let href = attribute("href", in: tail), let target = resolve(href) else { continue }
            found.append(WebSearchResult(
                title: text(after: tail),
                url: target,
                snippet: snippet(after: mark.upperBound, in: html)
            ))
        }
        return found
    }

    /// `name="value"`, read within the attribute window.
    static func attribute(_ name: String, in region: Substring) -> String? {
        let window = region.prefix(attributeWindow)
        guard let open = window.range(of: "\(name)=\"") else { return nil }
        let rest = window[open.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    /// The visible text of one element: what sits between the tag's `>` and the next `<`.
    static func text(after region: Substring) -> String {
        let window = region.prefix(attributeWindow)
        guard let open = window.firstIndex(of: ">") else { return "" }
        let body = window[window.index(after: open)...]
        let end = body.firstIndex(of: "<") ?? body.endIndex
        return oneLine(String(body[..<end]))
    }

    private static func snippet(after index: String.Index, in html: String) -> String {
        let tail = html[index...]
        guard let mark = tail.range(of: snippetMarker) else { return "" }
        return text(after: tail[mark.upperBound...])
    }

    /// This endpoint routes its links through its own redirector, so the real address is the `uddg`
    /// parameter, percent-encoded. Anything that does not decode to an http(s) address is dropped — a
    /// result Cairn cannot name is a result it should not hand to a model.
    static func resolve(_ href: String) -> String? {
        let cleaned = HTMLTextExtractor.decodeEntities(href.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let mark = cleaned.range(of: "uddg=") else {
            return cleaned.hasPrefix("http") ? cleaned : nil
        }
        let value = cleaned[mark.upperBound...].prefix { $0 != "&" && !$0.isWhitespace }
        guard let decoded = String(value).removingPercentEncoding, decoded.hasPrefix("http") else {
            return nil
        }
        return decoded
    }

    private static func oneLine(_ text: String) -> String {
        HTMLTextExtractor.collapse(HTMLTextExtractor.decodeEntities(text))
            .replacingOccurrences(of: "\n", with: " ")
    }
}
