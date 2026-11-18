import Foundation

/// Page markup in, readable text out.
///
/// No HTML parser dependency and no regular expressions: the tags are walked once, the elements that
/// are never prose (script, style, navigation, forms) are skipped whole rather than stripped after the
/// fact, and a block-level tag becomes a line break so the text keeps the shape a reader would see.
/// Cairn does not summarise a page it has not read, so this output is what the model gets — which is
/// why the noise that stays in would be a claim about the page that the page never made.
enum HTMLTextExtractor {
    /// The extraction cap, well under the tool's own byte bound so the clip in the registry still
    /// reports truncation honestly rather than hiding it behind a second, quieter cap.
    static let characterLimit = 12_000

    private static let skippedElements: Set<String> = [
        "script", "style", "noscript", "template", "head", "svg", "nav", "aside", "form", "iframe",
    ]

    private static let blockElements: Set<String> = [
        "p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "td", "th", "section",
        "article", "blockquote", "pre", "table", "ul", "ol", "dl", "dt", "dd", "figcaption", "main",
    ]

    static func extract(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return extract(from: text)
    }

    static func extract(from html: String) -> String {
        let region = contentRegion(of: html)
        var out = ""
        var index = region.startIndex
        while index < region.endIndex {
            let character = region[index]
            guard character == "<" else {
                out.append(character)
                index = region.index(after: index)
                continue
            }
            guard let close = region[index...].firstIndex(of: ">") else { break }
            let tag = region[region.index(after: index)..<close]
            var next = region.index(after: close)
            let name = tagName(of: tag)
            if let name, skippedElements.contains(name),
               let end = endOfElement(named: name, in: region, after: next) {
                next = end
            } else if let name, blockElements.contains(name) {
                out.append("\n")
            }
            index = next
        }
        return cap(decodeEntities(collapse(out)))
    }

    /// The article before the chrome: a page's own `main` or `article` element if it names one, its
    /// body if not, and the document as read if there is no body at all. Falling back rather than
    /// returning nothing is what makes a hand-rolled page still readable.
    private static func contentRegion(of html: String) -> Substring {
        for marker in ["<main", "<article", "<body"] where html.range(of: marker) != nil {
            guard let open = html.range(of: marker) else { continue }
            let start = html.index(after: open.upperBound)
            let name = String(marker.dropFirst(1))
            let tail = html[start...]
            if let end = tail.range(of: "</\(name)") { return tail[..<end.lowerBound] }
            return tail
        }
        return Substring(html)
    }

    /// `div` from `<div class="x">` and `</div>` alike; nil for a comment or a stray angle bracket.
    private static func tagName(of tag: Substring) -> String? {
        var body = tag
        if body.hasPrefix("/") { body = body.dropFirst() }
        if body.hasPrefix("!") || body.hasPrefix("?") { return nil }
        var name = ""
        for character in body {
            if character.isLetter { name.append(character.lowercased()) } else { break }
        }
        return name.isEmpty ? nil : name
    }

    /// Past the whole element, matched on its closing tag. An unclosed element runs to the end of the
    /// region, which is the honest answer for malformed markup and never a crash.
    private static func endOfElement(named name: String, in region: Substring, after index: String.Index) -> String.Index? {
        guard let close = region[index...].range(of: "</\(name)") else { return region.endIndex }
        return close.upperBound
    }
}
