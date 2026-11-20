import Foundation

/// What a transfer button means, before anyone knows which machine is doing the pulling.
///
/// Three verbs and no more, because these are the three a person reaching for a four-gigabyte download
/// actually wants: stop it for now, start it again, stop it for good. Anything else a transfer can do — retry,
/// verify, delete — is either something the app does on its own or something that belongs to the Installed
/// list rather than to a progress bar.
///
/// The verbs are named here rather than at the button so the view model can decide what each one means on
/// the path it is on: a phone pause keeps the bytes and closes the connection, a server pause cancels that
/// server's own task, and a sheet that had to know the difference would be a sheet with two versions of every
/// rule in it.
public enum ModelTransferControl: String, Sendable, CaseIterable, Identifiable {
    case pause
    case resume
    case cancel

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .cancel: return "Cancel"
        }
    }

    /// The SF Symbol the button draws. Pause and Resume are the two symbols everyone already knows, which is
    /// the point: on a small screen the words and the glyph have to agree, or the label is doing the work and
    /// the glyph is decoration.
    public var symbolName: String {
        switch self {
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        case .cancel: return "xmark.circle"
        }
    }

    /// Whether this control is the one that costs something irreversible.
    ///
    /// A pause keeps everything; a cancel throws away every byte fetched so far. Only the second needs
    /// confirming, and asking about a pause would train a person to tap through warnings — which is how a
    /// Cancel confirmation stops meaning anything.
    public var destroysProgress: Bool { self == .cancel }

    /// The sentence a confirmation puts under a destructive button, naming what is lost rather than asking
    /// whether the person is sure.
    public static func lossLine(doneBytes: Int64?, totalBytes: Int64?) -> String {
        guard let doneBytes, doneBytes > 0 else {
            return "Cairn has not fetched anything yet, so nothing is lost."
        }
        let kept = ByteCountFormatter.string(fromByteCount: doneBytes, countStyle: .file)
        guard let totalBytes, totalBytes > 0 else {
            return "This throws away the \(kept) Cairn has already fetched."
        }
        let whole = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "This throws away the \(kept) of \(whole) Cairn has already fetched."
    }
}
