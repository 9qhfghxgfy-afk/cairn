import Foundation

/// Progress of one model download, emitted as it happens so the Download tab can stream it.
public enum ModelDownloadEvent: Sendable, Equatable {
    case planned(fileCount: Int, totalBytes: Int64?)
    case fileStarted(name: String)
    /// Nothing is arriving, and the system says why rather than failing: it is holding this file's
    /// connection open and waiting for a route back to the network. The screen has to say so — a bar
    /// that stops moving with no explanation reads as a crash, and the person stops a transfer that was
    /// seconds from carrying on. It is the one event that carries no byte counts, because a wait
    /// invents none.
    case waiting(name: String)
    case fileProgress(name: String, update: DownloadProgressUpdate)
    case fileFinished(name: String, verified: Bool)
    case paused(name: String)
    case completed(totalBytes: Int64)
    case failed(message: String)
}

/// Why a download stopped, with whatever the transport knew attached to it.
///
/// No raw value: two of these carry a payload — the status the server refused with, and the words the transfer
/// produced — and a raw-value enum cannot hold either. Nothing ever read the raw value; the one thing read off
/// this type is `message`.
public enum ModelDownloadFailure: Sendable, Equatable, Error {
    case outboundNotOptedIn
    case invalidRepoID
    case noFilesListed
    case noStorage
    case verificationFailed
    /// The server refused the file, and kept the number rather than a generic sentence.
    ///
    /// A download task does not fail on a refusal — it reports a finished transfer whose bytes are the server's
    /// error page — so without this case a 401, a 403 and a 404 all arrive at the sheet as "the download
    /// failed", which is a sentence that sends a person to nowhere in particular.
    case refusedByServer(status: Int)
    /// The transfer itself broke, carrying the transport's own words (a network code, never a URL or a body).
    case transferFailed(message: String)

    public var message: String {
        switch self {
        case .outboundNotOptedIn:
            return "Downloading a model leaves the device. Turn on network access in Settings first."
        case .invalidRepoID: return "That is not a valid repository name."
        case .noFilesListed: return "This repository has no readable file list."
        case .noStorage: return "Cairn cannot reach its model storage."
        case .verificationFailed: return "The downloaded file did not match its published checksum."
        case .refusedByServer(let status): return HTTPTransferStatus.refusal(status)
        case .transferFailed(let message): return message
        }
    }
}


/// The opt-in rule for pulling a model, kept next to the code that performs the pull.
///
/// Every model download is public-internet traffic, so this is the same rule the server profiles
/// use: no outbound request without an explicit opt-in, and the badge stays up afterwards. It is a
/// type rather than a boolean parameter so a caller cannot forget to pass it.
public struct OutboundGate: Sendable, Equatable {
    public var isOptedIn: Bool

    public init(optedIn: Bool) {
        self.isOptedIn = optedIn
    }

    public func assertAllowsDownload() throws {
        guard isOptedIn else { throw ModelDownloadFailure.outboundNotOptedIn }
    }
}
