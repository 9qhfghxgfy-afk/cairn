import Foundation
import CairnChatDomain

/// Naming a failure from what the network or the status line actually said.
///
/// This belongs in the transport module rather than the domain because it is a statement about
/// URLSession: the domain's taxonomy is `blocked`/`unreachable`/`timedOut`, and this file is the only
/// place that knows which `URLError` means which.
///
/// **The local-network case is a heuristic, and is labelled as one.** iOS does not hand back a distinct
/// error code for "the user has not granted Local Network access" — it presents as a permission refusal
/// whose shape has varied by iOS version. The classification below treats a permission-style POSIX error
/// (`EPERM`) as that refusal because it is the shape the denial has been reported with, and it is the only
/// case here that guesses. Everything a guess gets wrong is still a typed failure with a Settings route,
/// never a silent retry.
extension WebSearchFailure {
    /// The status line, read as a fact about the provider rather than as "HTTP failed".
    static func response(status: Int) -> WebSearchFailure {
        switch status {
        case 401: return .providerUnavailable       // the credential was refused, so the row is not usable
        case 403: return .blocked
        case 404: return .invalidEndpoint           // nothing is at that path: the address is wrong
        case 429: return .rateLimited
        case 200..<300: return .unrecognizedResponse    // a success the reader could not use is a shape problem
        default: return status >= 500 ? .unreachable : .unrecognizedResponse
        }
    }

    /// A thrown error, mapped. Anything unmapped stays `unreachable` rather than becoming a crash or a
    /// blank result. Cancellation is not a search failure and is handled by the caller, which has the
    /// turn's own `.cancelled` to report.
    static func transport(_ error: any Error) -> WebSearchFailure {
        let urlError = (error as? URLError)
            ?? ((error as NSError).domain == NSURLErrorDomain ? URLError((error as NSError).code) : nil)
        guard let urlError else { return .unreachable }
        switch urlError.code {
        case .timedOut: return .timedOut
        case .unsupportedURL, .badURL: return .invalidEndpoint
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return .httpsRequired
        case .networkConnectionLost, .cannotConnectToHost:
            return isLocalNetworkDenial(urlError) ? .localNetworkDenied : .unreachable
        default:
            return .unreachable
        }
    }

    /// The guessed half, kept in one function so the guess is easy to find and easy to delete.
    ///
    /// `URLError.posix` is only populated for a failure that came back with a real errno, so a nil here
    /// means "no evidence", which is answered as `unreachable` rather than as a permission claim.
    private static func isLocalNetworkDenial(_ error: URLError) -> Bool {
        error.posix?.rawValue == 1   // EPERM: what a Local Network refusal has been reported as
    }
}
