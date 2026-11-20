import CairnChatDomain
import Foundation

/// The two public Hugging Face URLs this app can build, and the privacy rule attached to them.
///
/// Both are public-internet requests, so `NetworkClass.publicInternet` applies: the caller must hold
/// an explicit outbound opt-in and the outbound badge must be showing before either is fetched.
/// That gate is checked in `ModelDownloadManager`, not left to the UI to remember.
public enum HuggingFaceEndpoints {
    public static let host = "huggingface.co"

    /// The published file listing for a repository, with the digest each file publishes.
    ///
    /// `?blobs=true` is what makes this the right endpoint rather than a stylistic choice: it returns
    /// every file's `size` and, for a large file, its `lfs.sha256`. The alternative
    /// (`/api/models/<id>/tree/main`) returns a git object id, which is a hash of the pointer file, not
    /// of the bytes — comparing a downloaded weight against it would either fail a good download or, if
    /// skipped, leave every weight installed unverified.
    public static func fileListing(repoID: String) -> URL? {
        guard let id = HuggingFaceRepoID.parse(repoID).repoID else { return nil }
        return URL(string: "https://\(Self.host)/api/models/\(id)?blobs=true")
    }

    /// A single raw file. Downloading resumes from this same URL with a stored resume block.
    public static func fileURL(repoID: String, name: String) -> URL? {
        guard let id = HuggingFaceRepoID.parse(repoID).repoID,
              Self.isSafeFileName(name)
        else { return nil }
        return URL(string: "https://\(Self.host)/\(id)/resolve/main/\(name)")
    }

    /// Every request this file can build leaves the device for a public host.
    public static var networkClass: NetworkClass { .publicInternet }

    /// One fixed identity on every request this module makes, redirects included.
    ///
    /// The same string `CairnProviderRemote` sends, so the app presents one identity to every server rather
    /// than a different one per code path. A download with no user agent at all is the other option, and it
    /// is worse for the user: a content delivery network that cannot tell what is asking answers with a
    /// throttled socket, which is what a bar that stops moving usually is. Nothing identifying is in it.
    public static let userAgent = "Cairn/1.0 (local-first assistant)"

    /// The headers a request to the Hub may carry, and the only place that decides it.
    ///
    /// `Authorization` appears only when a token was saved for it, because a public model is fetched the
    /// same way whether or not this phone holds a credential — the token is an extra, not a requirement.
    /// The value is handed in by the caller, which reads it from the Keychain at the moment the request is
    /// built; nothing here stores it, and nothing here logs it.
    public static func authorizedHeaders(token: String?) -> [String: String] {
        var headers = ["User-Agent": userAgent]
        guard let token else { return headers }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return headers }
        headers["Authorization"] = "Bearer \(trimmed)"
        return headers
    }

    /// Whether a credential may travel from one request to the next.
    ///
    /// The Hub hands out the weight files by redirecting to a storage host the person never named. A token
    /// pasted for `huggingface.co` is consent to be recognised there, not on whichever machine the Hub
    /// chose to serve the bytes from, so a cross-host redirect goes out without it. Same-host redirects keep
    /// it, which is what lets an authenticated retry of the same host still work.
    public static func mayCarryCredential(from source: URL?, to destination: URL?) -> Bool {
        guard let source = source?.host?.lowercased(),
              let destination = destination?.host?.lowercased(),
              !source.isEmpty else { return false }
        return source == destination
    }

    /// A file name from a remote listing is still just a name: no parent traversal, no leading
    /// slash, no scheme. It is joined onto a directory the app owns, so this is what keeps a
    /// hostile listing from writing outside it.
    public static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 200, !name.hasPrefix("/") else { return false }
        if name.contains("://") || name.contains("\\") { return false }
        let segments = name.split(separator: "/", omittingEmptySubsequences: false)
        return segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
