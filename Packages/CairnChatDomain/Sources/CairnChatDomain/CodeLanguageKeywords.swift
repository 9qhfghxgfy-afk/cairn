import Foundation

/// The keyword tables behind `CodeLanguage`.
///
/// These are reserved words and literals taken from each language's own published grammar, not from a
/// model's habit of naming things. A word a language treats as an ordinary identifier stays out of the
/// table: `print` is not a keyword in Swift and `len` is not one in Python, so colouring one as a
/// keyword is a claim about the language that is simply false.
extension CodeLanguage {

    static func keywords(for language: CodeLanguage) -> Set<String> {
        switch language {
        case .swift: return swiftKeywords
        case .python: return pythonKeywords
        case .cFamily: return cFamilyKeywords
        case .javaScript: return javaScriptKeywords
        case .json: return jsonKeywords
        case .go: return goKeywords
        case .ruby: return rubyKeywords
        case .rust: return rustKeywords
        case .shell: return shellKeywords
        case .sql: return sqlKeywords
        case .yaml: return yamlKeywords
        case .unknown: return []
        }
    }

    /// Swift's declarations and control flow, plus the literals the compiler itself defines.
    static let swiftKeywords: Set<String> = [
        "associatedtype", "await", "break", "case", "catch", "class", "continue", "convenience",
        "default", "defer", "deinit", "didSet", "do", "each", "else", "enum", "extension", "fallthrough",
        "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "indirect", "init", "inout",
        "internal", "is", "lazy", "let", "macro", "mutating", "nil", "nonisolated", "nonmutating", "open",
        "operator", "optional", "override", "package", "private", "protocol", "public", "repeat",
        "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "true", "try", "typealias", "unchecked", "where", "while", "willSet",
    ]

    static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
        "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is",
        "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while",
        "with", "yield", "match", "case",
    ]

    /// C, C++, Objective-C, Java, Kotlin and C# share enough shape to share one table; a word that
    /// differs between them is an ordinary identifier in the others rather than a reserved one.
    static let cFamilyKeywords: Set<String> = [
        "auto", "bool", "break", "case", "catch", "char", "class", "const", "constexpr", "continue",
        "default", "delete", "do", "double", "else", "enum", "explicit", "extern", "false", "final",
        "float", "for", "friend", "goto", "if", "inline", "int", "interface", "long", "mutable",
        "namespace", "new", "nullptr", "NULL", "operator", "override", "private", "protected", "public",
        "register", "return", "sealed", "short", "signed", "sizeof", "static", "struct", "switch",
        "template", "this", "throw", "true", "try", "typedef", "typename", "union", "unsigned", "using",
        "virtual", "void", "volatile", "while", "var", "val", "fun", "when", "nil", "null", "YES", "NO",
    ]

    static let javaScriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
        "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "get",
        "if", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "return", "set",
        "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var",
        "void", "while", "with", "yield",
    ]

    static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
        "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
        "struct", "switch", "type", "var", "true", "false", "nil", "iota",
    ]

    static let rubyKeywords: Set<String> = [
        "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
        "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue",
        "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while",
        "yield",
    ]

    static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
        "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
        "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
        "use", "where", "while",
    ]

    /// The shell builtins a reader scans for, not every binary on a PATH.
    static let shellKeywords: Set<String> = [
        "bash", "break", "case", "cd", "continue", "do", "done", "echo", "elif", "else", "esac", "exit",
        "export", "fi", "for", "function", "if", "in", "local", "read", "return", "set", "shift",
        "source", "then", "trap", "until", "while",
    ]

    /// SQL is drawn case-insensitively, so the table is lowercase and the scanner lowercases the word
    /// before it looks here.
    static let sqlKeywords: Set<String> = [
        "add", "all", "alter", "and", "as", "begin", "between", "by", "column", "commit", "constraint",
        "create", "default", "delete", "distinct", "drop", "end", "exists", "foreign", "from", "group",
        "having", "in", "index", "insert", "into", "is", "join", "key", "like", "limit", "not", "null",
        "offset", "on", "or", "order", "primary", "references", "rename", "replace", "returning",
        "rollback", "select", "set", "table", "transaction", "union", "unique", "update", "using",
        "values", "when", "where", "with",
    ]

    static let yamlKeywords: Set<String> = ["true", "false", "null", "yes", "no", "on", "off"]

    /// JSON has three value words and no declarations, so its whole vocabulary is those three. Colouring
    /// a key as a keyword because it appears left of a colon would be a claim JSON does not make.
    static let jsonKeywords: Set<String> = ["true", "false", "null"]
}
