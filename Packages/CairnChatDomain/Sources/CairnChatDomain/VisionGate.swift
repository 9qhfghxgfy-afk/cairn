import Foundation

/// What may be done with the images on a turn.
///
/// The rule this file exists to make impossible: an image disappearing on the way to a model that
/// cannot see. Silently dropping an attachment makes the answer look like it ignored a file the user
/// can still see on their own screen, and a model that was never given the pixels will still describe
/// a plausible one. So a turn that carries an image and an engine that cannot see does not send — and
/// says which of the two it needs the user to change.
public enum VisionDecision: Sendable, Equatable {
    /// Nothing attached: nothing to gate.
    case nothingAttached
    /// The engine declares it accepts images, so the bytes travel with the turn.
    case allows(imageCount: Int)
    /// The engine has not been seen to accept images. The turn is refused, not stripped.
    case cannotSee(imageCount: Int)

    public var blocksSend: Bool {
        if case .cannotSee = self { return true }
        return false
    }

    public var imageCount: Int {
        switch self {
        case .nothingAttached: return 0
        case .allows(let count): return count
        case .cannotSee(let count): return count
        }
    }
}

public enum VisionGate {
    /// `modelSees` is the engine's declared capability, never an assumption about a model class — the
    /// same rule every other capability in Cairn follows.
    public static func decide(imageCount: Int, modelSees: Bool) -> VisionDecision {
        guard imageCount > 0 else { return .nothingAttached }
        return modelSees ? .allows(imageCount: imageCount) : .cannotSee(imageCount: imageCount)
    }

    public static func decide(
        attachments: [ChatAttachment], modelSees: Bool
    ) -> VisionDecision {
        decide(imageCount: Attachments.images(attachments).count, modelSees: modelSees)
    }

    /// What the composer and the error line say. One wording for one situation, so the chip's warning
    /// and the refusal on send cannot drift into two different explanations.
    public static func message(for decision: VisionDecision) -> String? {
        switch decision {
        case .nothingAttached, .allows:
            return nil
        case .cannotSee(let count):
            let what = count == 1 ? "one image" : "\(count) images"
            return "This model has not been seen to accept images, and this turn carries \(what). "
                + "Choose a model that can see them, or remove the image and send the text alone — "
                + "Cairn will not quietly drop what you attached."
        }
    }

    /// The standing line above the composer while an image is staged against a model that cannot see.
    public static func warning(for attachments: [ChatAttachment], modelSees: Bool) -> String? {
        message(for: decide(attachments: attachments, modelSees: modelSees))
    }
}
