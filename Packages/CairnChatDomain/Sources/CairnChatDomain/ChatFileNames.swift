import Foundation

/// A chat title turned into a file name.
///
/// A chat title is whatever a model's first line happened to be, and that line can contain a slash, a
/// colon, a newline or a string of emoji. Handing such a name to a filesystem, or to another app through a
/// share sheet, is how a chat ends up written somewhere unexpected or refused on the way out. So the name
/// is narrowed to what a filename can hold, and nothing else about the device is put into it — no user
/// name, no path, no hostname.
public enum ChatFileNames {

    /// The fallback for a title with nothing usable in it.
    public static let fallback = "cairn-chat"

    /// One path segment: letters, digits, spaces (turned into dashes), dot, underscore and hyphen.
    ///
    /// `maxLength` bounds the stem rather than the whole name, because a chat title can be a whole
    /// paragraph and a file browser should still show what the file is.
    public static func safeSegment(_ title: String, maxLength: Int = 60) -> String {
        var pieces: [Character] = []
        var previousWasSeparator = false
        for character in title {
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                pieces.append(character)
                previousWasSeparator = false
                continue
            }
            // Everything else — a slash, a colon, a newline, an emoji — becomes one dash, collapsed. A
            // title that reads like a path must not come out as one, and dropping the character instead
            // would fuse two words into something neither is.
            guard !previousWasSeparator, !pieces.isEmpty else { continue }
            pieces.append("-")
            previousWasSeparator = true
        }
        // A name that starts with a dot is invisible on every unix-shaped filesystem, and one that ends
        // with a dot or a dash is rejected by some of them.
        while let last = pieces.last, last == "-" || last == "." || last == "_" { pieces.removeLast() }
        while let first = pieces.first, first == "-" || first == "." || first == "_" { pieces.removeFirst() }

        var stem = String(pieces)
        if stem.count > maxLength {
            stem = String(stem.prefix(maxLength))
            while let last = stem.last, last == "-" || last == "." || last == "_" { stem.removeLast() }
        }
        return stem.isEmpty ? fallback : stem
    }

    /// The name an export should use: the chat's own title, or a date-stamped name for the all-chats file.
    ///
    /// Lives here rather than on the workspace because a file name is not app state — and a static on a
    /// `@MainActor` class cannot be called from a plain function, which is what makes a name hard to test.
    public static func name(for chat: Conversation?, markdown: Bool, now: Date = Date()) -> String {
        let suffix = markdown ? "md" : "cairn"
        guard let chat else { return "cairn-chats-\(now.iso8601.prefix(10)).\(suffix)" }
        let stem = safeSegment(ChatListQuery.visibleTitle(chat))
        // Two chats whose titles were never typed would otherwise export to the same name, and a name the
        // user cannot tell apart in a file list is a name that gets overwritten.
        if ChatListQuery.visibleTitle(chat) == ChatListQuery.untitledTitle {
            return "\(stem)-\(now.iso8601.prefix(10)).\(suffix)"
        }
        return "\(stem).\(suffix)"
    }
}
