import Foundation

/// The languages Cairn colours, and the honest answer for every other one.
///
/// A language is a table of what to look for, not a grammar. Each entry is a set of words rather than a
/// parser: colouring a word this language does not have would tell the user something false about the
/// code, so an unknown fence names no table and comes out plain. `.unknown` is a real case, not a
/// fallback to Swift.
public enum CodeLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case swift
    case python
    case cFamily
    case javaScript
    case go
    case ruby
    case rust
    case shell
    case sql
    case json
    case yaml
    case unknown

    /// The fence's info string mapped to a table. Aliases are the ones a model actually writes.
    public init(infoString: String?) {
        switch infoString?.trimmingCharacters(in: .whitespaces) ?? "" {
        case "swift": self = .swift
        case "python", "py", "python3": self = .python
        case "c", "h", "cpp", "c++", "cxx", "objc", "objective-c", "java", "kotlin", "kt", "cs", "csharp":
            self = .cFamily
        case "js", "javascript", "ts", "typescript", "tsx", "jsx", "node": self = .javaScript
        case "go", "golang": self = .go
        case "rb", "ruby": self = .ruby
        case "rs", "rust": self = .rust
        case "sh", "bash", "zsh", "shell", "console": self = .shell
        case "sql", "psql", "mysql", "sqlite": self = .sql
        case "json", "jsonc", "json5": self = .json
        case "yaml", "yml", "toml": self = .yaml
        default: self = .unknown
        }
    }

    /// The words that mean something in this language, kept per family rather than shared — a keyword in
    /// one language is an ordinary name in another, and one shared list would colour both wrongly.
    public var keywords: Set<String> { CodeLanguage.keywords(for: self) }

    /// Where a comment runs to end of line, or nil for a language with no comment syntax of its own.
    /// JSON is nil here on purpose: it has no comments, and treating `//` as one would colour a URL
    /// inside a value as though the file were JavaScript.
    public var lineComment: String? {
        switch self {
        case .swift, .cFamily, .javaScript, .go, .rust: return "//"
        case .python, .ruby, .shell, .yaml: return "#"
        case .sql: return "--"
        case .json, .unknown: return nil
        }
    }

    /// A comment that can span lines. Cairn carries the open state across the lines of one block, so a
    /// mid-block opener does not end colourless.
    public var blockComment: (open: String, close: String)? {
        switch self {
        case .swift, .cFamily, .javaScript, .go, .rust, .sql: return ("/*", "*/")
        case .python, .ruby, .shell, .json, .yaml, .unknown: return nil
        }
    }

    /// The characters that open a string literal in this language. JSON is double-quote only — a single
    /// quote inside a JSON value is an apostrophe, not the start of a literal.
    public var stringDelimiters: Set<Character> {
        switch self {
        case .unknown: return []
        case .json: return ["\""]
        case .sql: return ["'", "\""]
        default: return ["\"", "'"]
        }
    }

    /// Whether a word with no keyword match is worth naming as a type. A language that does not
    /// capitalise its names (SQL, shell, YAML, JSON) gets no name colour rather than a colour from
    /// nothing.
    public var namesTypesByCapital: Bool {
        switch self {
        case .swift, .cFamily, .javaScript, .go, .rust, .python, .ruby: return true
        case .shell, .sql, .yaml, .json, .unknown: return false
        }
    }
}
