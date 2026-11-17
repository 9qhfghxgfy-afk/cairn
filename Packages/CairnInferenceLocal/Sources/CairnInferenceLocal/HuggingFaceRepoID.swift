import Foundation

/// Why a typed model name cannot be used. Each case maps to one sentence in the UI, because "invalid"
/// teaches the user nothing about what to type instead.
public enum RepoIDRejection: String, Sendable, Equatable, CaseIterable {
    case empty
    case looksLikeURL
    case pathTraversal
    case hasWhitespace
    case missingNamespace
    case illegalCharacter
    case tooLong

    public var message: String {
        switch self {
        case .empty: return "Enter an owner and a repository name."
        case .looksLikeURL: return "Enter the repository name, not a web address."
        case .pathTraversal: return "The name cannot refer to a parent folder."
        case .hasWhitespace: return "The name cannot contain spaces."
        case .missingNamespace: return "Use the form owner/repository."
        case .illegalCharacter: return "The name has a character that is not allowed."
        case .tooLong: return "The name is too long."
        }
    }
}

public enum RepoIDParseResult: Sendable, Equatable {
    case valid(String)
    case rejected(RepoIDRejection)

    public var repoID: String? {
        if case .valid(let id) = self { return id }
        return nil
    }
}

/// The rule for "type the exact name to install".
///
/// An owner/name pair is turned into a filesystem path and into a request, so the shape is checked
/// before either happens: no scheme, no host, no `..`, no whitespace, no separator other than `/`,
/// and a bounded length. This is the only thing that stands between a typed string and the disk.
public enum HuggingFaceRepoID {
    public static let maxLength = 200

    /// Characters legal in an owner or repository segment. `/` is handled separately as the
    /// separator, so it can never appear here.
    private static let legalSegment: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "._-")
        return set
    }()

    public static func parse(_ raw: String) -> RepoIDParseResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .rejected(.empty) }
        guard text.count <= maxLength else { return .rejected(.tooLong) }
        if text.contains("://") || text.hasPrefix("www.") { return .rejected(.looksLikeURL) }
        if text.contains("/") == false { return .rejected(.missingNamespace) }
        if text.contains("\\") { return .rejected(.illegalCharacter) }

        let segments = text.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments {
            if segment.isEmpty { return .rejected(.illegalCharacter) }
            if segment == "." || segment == ".." { return .rejected(.pathTraversal) }
            if segment.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                return .rejected(.hasWhitespace)
            }
            if segment.unicodeScalars.contains(where: { !legalSegment.contains($0) }) {
                return .rejected(.illegalCharacter)
            }
        }
        return .valid(segments.joined(separator: "/"))
    }

    public static func isValid(_ raw: String) -> Bool {
        parse(raw).repoID != nil
    }
}
