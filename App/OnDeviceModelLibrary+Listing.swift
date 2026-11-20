import Foundation
import CairnChatDomain
import CairnInferenceLocal

/// The listing half of the phone's own library: one request, for one repository's published files.
///
/// The listing is what makes a checksum verifiable, so it is fetched rather than assumed — a download
/// without a listing cannot be checked, and the manager refuses to call those bytes installed. It is also
/// the one Hub request in this app that is not a file transfer, which makes it the other place a saved
/// credential has to be attached: a repository whose terms must be accepted first answers an anonymous
/// listing with a refusal, and the message the person would then get — "the repository would not list its
/// files (status 401)" — is true and useless at the same time.
extension OnDeviceModelLibrary {
    func fetchListing(_ repoID: String) async throws -> [ModelFileListing] {
        guard let url = HuggingFaceEndpoints.fileListing(repoID: repoID) else {
            throw CairnLibraryError.badRepository
        }
        var request = URLRequest(url: url)
        // Thirty seconds, and no cache. A listing is read to decide what to fetch and what to verify
        // afterwards; a cached copy is a file list from some earlier moment, and a checksum checked
        // against the wrong published digest is a good download called a bad one.
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for (field, value) in HuggingFaceEndpoints.authorizedHeaders(token: tokens?.token(for: .huggingFace)) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request, delegate: ListingRedirectGuard())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CairnLibraryError.listingRefused(status)
        }
        return ModelFilePlan.listing(from: data)
    }
}

/// Stops a credential at the host it was written for, for one request.
///
/// `URLSession.shared` forwards a request's `Authorization` header through a redirect, and the Hub is free
/// to answer from wherever it likes. A per-task delegate is the cheapest way to keep the same rule the
/// download path keeps: it is retained for the life of the task, it overrides the session's own handling,
/// and it costs no session to create or invalidate. Stateless, so the `@unchecked Sendable` records a fact
/// rather than excusing one.
private final class ListingRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var onward = request
        if !HuggingFaceEndpoints.mayCarryCredential(from: task.currentRequest?.url, to: request.url) {
            for field in ["Authorization", "X-API-Key", "Api-Key", "Cookie"] {
                onward.setValue(nil, forHTTPHeaderField: field)
            }
        }
        completionHandler(onward)
    }
}
