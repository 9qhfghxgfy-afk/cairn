import CairnChatDomain
import Foundation

/// The two public Hugging Face URLs this app can build, and the privacy rule attached to them.
///
/// Both are public-internet requests, so `NetworkClass.publicInternet` applies: the caller must hold
/// an explicit outbound opt-in and the outbound badge must be showing before either is fetched.
/// That gate is checked in `ModelDownloadManager`, not left to the UI to remember.
public enum HuggingFaceEndpoints {
    public static let host = "huggingface.co"

    /// The published file listing for a repository's default branch.
    public static func fileListing(repoID: String) -> URL? {
        guard let id = HuggingFaceRepoID.parse(repoID).repoID else { return nil }
        return URL(string: "https://\(Self.host)/api/models/\(id)/tree/main")
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
