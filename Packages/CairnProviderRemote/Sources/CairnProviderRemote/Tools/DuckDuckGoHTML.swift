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
    /// DuckDuckGo's own class for a sponsored result.
    private static let adMarker = "result--ad"
    /// What a bot page says about itself. The endpoint answers a challenge with an ordinary page rather
    /// than a status a client could read, so the words are the only signal there is — and they are read
    /// before the empty markers, because a refusal taken for "found nothing" sends the user away convinced
    /// the web has no answer when in fact this client was refused one.
    private static let challengeMarkers = [
        "captcha", "unusual traffic", "are you a robot", "confirm you are not a bot",
    ]

    /// How far past a marker to look for its attributes, so one malformed page cannot make the scan
    /// walk a whole document.
    private static let attributeWindow = 400

    /// What kind of page this endpoint sent back, told apart by its markers.
    ///
    /// The distinction is the whole point of this type: a page with no result markers may be an honest
    /// "nothing found", or it may be a page whose markup moved. Reading the second as the first is how a
    /// broken provider ends up telling the user that nothing exists.
    enum PageKind: Sendable, Equatable {
        case results
        case empty
        /// A challenge page: the endpoint refused this client rather than answering it. Reported as
        /// blocked, never as an empty result list.
        case challenge
        case unrecognized
    }

    static func pageKind(in html: String) -> PageKind {
        if html.contains(anchorMarker) { return .results }
        let lowered = html.lowercased()
        if challengeMarkers.contains(where: { lowered.contains($0) }) { return .challenge }
        if lowered.contains("no results") || lowered.contains("no-results")
            || lowered.contains("did not match any documents") { return .empty }
        return .unrecognized
    }

    static func results(in html: String, limit: Int) -> [WebSearchResult] {
        var found: [WebSearchResult] = []
        var seen = Set<String>()
        var search = Substring(html)
        while found.count < max(1, limit), let mark = search.range(of: anchorMarker) {
            let tail = search[mark.upperBound...]
            search = tail
            guard !isAd(mark, in: html),
                  let href = attribute("href", in: tail),
                  let target = resolve(href),
                  !seen.contains(target)
            else { continue }
            seen.insert(target)
            found.append(WebSearchResult(
                title: text(after: tail),
                url: target,
                snippet: snippet(after: mark.upperBound, in: html)
            ))
        }
        return found
    }

    /// Sponsored results are dropped rather than labelled.
    ///
    /// A tool result is plain text handed to a model, which has no badge to read and every reason to cite
    /// whatever is in front of it. A paid link presented as a source is a source that was bought, so it is
    /// not in the list at all. The class is looked for just before the anchor because that is where the
    /// enclosing element carries it.
    private static func isAd(_ mark: String.Index, in html: String) -> Bool {
        html[html.startIndex...mark].suffix(240).contains(adMarker)
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
