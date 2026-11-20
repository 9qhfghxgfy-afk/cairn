import Foundation

/// The words a broken transfer takes, chosen from the network code the system reports.
///
/// A code is the only part of a transport failure worth putting on a screen: it says which of the four things
/// happened — the line went quiet, the route dropped, the host would not answer, the phone ran out of room — and
/// each one sends a person somewhere different. "The download failed" sends them nowhere, which is how a phone
/// with no Wi-Fi ends up being blamed for a stalled socket.
///
/// The code travels with the sentence because it is typed metadata: no URL, no header, no response body, no
/// token. Whatever the server said stays out of this file entirely.
enum NetworkFault {
    /// The secure-connection and certificate family, as reported by the URL loader: -1200 is a connection that
    /// could not be established securely, -1202 to -1204 are a certificate that is untrusted, rooted badly, or
    /// not yet valid, -1205 and -1206 are a client certificate that was rejected or that the server demands.
    ///
    /// The band is the honest way to name this family from a machine that cannot compile against the Apple
    /// headers; it catches every member of it and nothing else, because nothing else in URL loading reports a
    /// number in that range.
    static let certificateBand: ClosedRange<Int> = -1206 ... -1200

    static func message(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorTimedOut:
            return "The transfer went silent for longer than Cairn waits for a stalled socket (network error "
                + "\(error.code)). What was fetched is kept; Resume picks it up from there."
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
            return "The connection to the Hub dropped (network error \(error.code)). What was fetched is kept; "
                + "Resume picks it up from there."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "The Hub could not be reached from this phone (network error \(error.code))."
        case Self.certificateBand:
            // The certificate family is matched as a band of codes rather than by name. The Swift spellings of
            // these constants are not verifiable from the machine this is written on — the four names a first
            // draft used do not exist in Foundation at all, which a local typecheck caught — and the numbers are
            // what the system actually reports, so a band cannot drift the way a guessed identifier can. A wrong
            // number here only chooses a different sentence; it cannot break a download.
            return "The Hub's connection could not be verified (network error \(error.code)). A network that "
                + "intercepts TLS is the usual reason — a captive portal or a corporate proxy."
        case NSFileWriteOutOfSpaceError:
            return "This phone has no room left for the file (storage error \(error.code)). Free some space "
                + "and start the download again."
        case NSURLErrorCancelled:
            return "The download was stopped."
        default:
            return "The download failed (network error \(error.code))."
        }
    }
}
