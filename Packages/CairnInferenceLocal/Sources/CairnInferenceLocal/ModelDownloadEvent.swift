import Foundation

/// Progress of one model download, emitted as it happens so the Download tab can stream it.
public enum ModelDownloadEvent: Sendable, Equatable {
    case planned(fileCount: Int, totalBytes: Int64?)
    case fileStarted(name: String)
    case fileProgress(name: String, update: DownloadProgressUpdate)
    case fileFinished(name: String, verified: Bool)
    case paused(name: String)
    case completed(totalBytes: Int64)
    case failed(message: String)
}

public enum ModelDownloadFailure: String, Sendable, Error {
    case outboundNotOptedIn
    case invalidRepoID
    case noFilesListed
    case noStorage
    case verificationFailed
    case transferFailed

    public var message: String {
        switch self {
        case .outboundNotOptedIn:
            return "Downloading a model leaves the device. Turn on network access in Settings first."
        case .invalidRepoID: return "That is not a valid repository name."
        case .noFilesListed: return "This repository has no readable file list."
        case .noStorage: return "Cairn cannot reach its model storage."
        case .verificationFailed: return "The downloaded file did not match its published checksum."
        case .transferFailed: return "The download failed."
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
