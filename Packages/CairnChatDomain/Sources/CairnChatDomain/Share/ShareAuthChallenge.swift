import Foundation

/// How a key check came out. Three cases, and the difference matters in the log-free UI:
/// "no key at all" and "wrong key" are different lines to show a user whose client keeps
/// refusing, and neither line may repeat the key it was given.
public enum ShareAuthOutcome: Sendable, Equatable {
    case accepted
    case missing
    case mismatch
}

/// The key check in front of every route, including the model list.
///
/// There is no unauthenticated route on this surface. `/api/tags` and `/v1/models` look harmless,
/// but they name the models on a person's phone and tell a stranger that the phone is there.
public enum ShareAuthChallenge {
    /// The key a client presented, from any of the spellings real clients use:
    /// `Authorization: Bearer …`, `Authorization: Token …`, or `X-API-Key: …`.
    public static func presentedToken(in request: ShareHTTPRequest) -> String? {
        if let value = request.header("x-api-key"), !value.isEmpty { return value }
        guard let raw = request.header("authorization") else { return nil }
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let scheme = parts[0].lowercased()
        guard scheme == "bearer" || scheme == "token" else { return nil }
        let token = String(parts[1])
        return token.isEmpty ? nil : token
    }

    public static func check(_ request: ShareHTTPRequest, expected: String) -> ShareAuthOutcome {
        guard let presented = presentedToken(in: request) else { return .missing }
        return matches(presented, expected) ? .accepted : .mismatch
    }

    /// Byte-by-byte compare over equal-length buffers.
    ///
    /// Not because a LAN attacker can mount a timing attack through a phone's socket — but because
    /// "stop after the first differing byte" leaks how much of a key was right, and a check written
    /// once gets reused. Length is compared first, so the loop never short-circuits on length.
    public static func matches(_ presented: String, _ expected: String) -> Bool {
        let left = [UInt8](presented.utf8)
        let right = [UInt8](expected.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<left.count { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}
