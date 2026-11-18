import Foundation

/// One stretch of a code line that shares a colour.
///
/// The kinds are the ones a reader can act on — a keyword, a name, a literal, a comment — and nothing
/// else. A highlighter that invents structure a language does not have is worse than one that draws the
/// line plain, so anything uncertain is `.plain`.
public struct CodeSpan: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case plain
        case keyword
        case name
        case string
        case number
        case comment
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public extension [CodeSpan] {
    /// The line rebuilt exactly as written. Highlighting must never change a character: the user can
    /// copy the block, and a highlighter that drops or reorders text would hand back broken code.
    var sourceText: String { map(\.text).joined() }

    /// Adjacent spans of the same kind merged, so a long identifier does not become fifty spans and the
    /// renderer's `AttributedString` stays small.
    var coalesced: [CodeSpan] {
        var out: [CodeSpan] = []
        for span in self {
            if var last = out.last, last.kind == span.kind {
                last.text += span.text
                out[out.count - 1] = last
            } else {
                out.append(span)
            }
        }
        return out
    }
}
