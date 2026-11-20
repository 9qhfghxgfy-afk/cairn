import Foundation

/// How one model transfer stands, whichever machine is doing the pulling.
///
/// Two paths exist and they report differently: an on-device transfer knows its byte counts because
/// Cairn is the one moving them, while a server pull reports the server's own status line and whatever
/// totals it chose to state. The Download sheet has to draw one thing, so both land here — and the
/// reason it is a type rather than two branches in a view is that a view with two branches drifts, and
/// a progress bar that lies about a denominator is the one thing this screen must not do.
///
/// A missing total stays missing. `percentText` answers "not stated" instead of drawing 0%, because a
/// bar that claims to know how far it has to go is a claim nobody made.
public enum ModelTransferStage: String, Sendable, Equatable {
    case queued
    case running
    case verifying
    case finished
    case stopped
    case failed

    public var isInFlight: Bool {
        switch self {
        case .queued, .running, .verifying: return true
        case .finished, .stopped, .failed: return false
        }
    }

    /// The state in Cairn's words. A failure keeps its own message instead, which is the reason
    /// `ModelTransferStatus.line` exists rather than this being the whole story.
    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Downloading"
        case .verifying: return "Checking the checksum"
        case .finished: return "Installed"
        case .stopped: return "Cancelled"
        case .failed: return "Failed"
        }
    }
}

public struct ModelTransferStatus: Sendable, Equatable {
    /// The entry this transfer belongs to, so a sheet closed over one model cannot draw another
    /// model's numbers.
    public var entryID: String
    public var stage: ModelTransferStage
    /// The status line in the words of whoever is doing the work. A server's own progress text is
    /// shown as written; paraphrasing it would be a claim about someone else's machine.
    public var line: String
    public var completedBytes: Int64?
    public var totalBytes: Int64?

    public init(
        entryID: String,
        stage: ModelTransferStage,
        line: String,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        self.entryID = entryID
        self.stage = stage
        self.line = line
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    /// A phone transfer, whose stages Cairn owns end to end. The words stay `LocalTransferState`'s
    /// own, so the same state cannot read differently in two screens.
    public init(entryID: String, state: LocalTransferState) {
        let stage: ModelTransferStage
        var done: Int64?
        var total: Int64?
        switch state {
        case .queued: stage = .queued
        case .running(let completedBytes, let totalBytes):
            stage = .running
            done = completedBytes
            total = totalBytes
        case .verifying: stage = .verifying
        case .installed(let bytes):
            stage = .finished
            done = bytes
            total = bytes
        case .stopped: stage = .stopped
        // A failure keeps its own message verbatim: "the file did not match its published checksum"
        // and "the download failed" are different facts, and only one of them means the bytes were bad.
        case .failed: stage = .failed
        }
        self.init(entryID: entryID, stage: stage, line: state.label,
                  completedBytes: done, totalBytes: total)
    }

    /// A server pull, whose only truth is the line the server sent. No stage is invented here: the
    /// server's text is shown, and the progress bar is drawn from its numbers or not at all.
    public init(entryID: String, pull: ModelPullProgress) {
        self.init(
            entryID: entryID,
            stage: .running,
            line: pull.statusText,
            completedBytes: pull.completedBytes,
            totalBytes: pull.totalBytes
        )
    }

    public var isInFlight: Bool { stage.isInFlight }

    /// nil whenever no denominator was ever named.
    public var fraction: Double? {
        guard stage.isInFlight, let totalBytes, totalBytes > 0, let completedBytes else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    public var percentText: String {
        guard let fraction else { return "not stated" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}
