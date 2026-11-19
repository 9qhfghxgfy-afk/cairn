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
    ///
    /// `as? URLError` is the whole read, deliberately: a URL failure that arrives as a bridged `NSError`
    /// comes back through Swift's error bridging as a `URLError`, and there is no portable way to rebuild a
    /// `URLError` from a raw `Int` — `URLError.Code(rawValue:)` is failable on one Foundation and not the
    /// other, which is a compile difference, not a runtime one. So an error that is not a `URLError` is
    /// simply not a URL failure, and gets the honest `unreachable`.
    static func transport(_ error: any Error) -> WebSearchFailure {
        guard let urlError = error as? URLError else { return .unreachable }
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
    /// `URLError` carries no errno of its own — there is no typed accessor for one — so the guess reads the
    /// bridged `NSError`: the failure itself, or the error underneath it, under the POSIX domain with the
    /// permission code. Absent either, there is no evidence, which is answered as `unreachable` rather than
    /// as a permission claim.
    private static func isLocalNetworkDenial(_ error: URLError) -> Bool {
        let bridged = error as NSError
        if isPermissionRefusal(bridged) { return true }
        guard let underlying = bridged.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isPermissionRefusal(underlying)
    }

    /// `EPERM` under the POSIX domain: the shape a Local Network refusal has been reported with. The errno
    /// is spelled numerically on purpose — Apple's Foundation names this `POSIXError` case, the portable one
    /// does not, so the number is the only spelling that compiles on both. It is read only beside the POSIX
    /// domain, so a bare `1` from another domain never reads as a refusal. No error text is read or logged.
    private static func isPermissionRefusal(_ candidate: NSError) -> Bool {
        candidate.domain == NSPOSIXErrorDomain && candidate.code == permissionRefusalErrno
    }

    private static let permissionRefusalErrno = 1
}
