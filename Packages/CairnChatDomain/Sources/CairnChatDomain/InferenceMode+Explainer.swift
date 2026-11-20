import Foundation

/// What a mode actually does, in words a person can read before choosing it.
///
/// The words sit beside the enum for the same reason `displayName` does: the mode is named in the
/// chat's switcher, in the list of chats, and in a popover, and a second copy of the description is
/// a second opinion about what the mode means — and the second copy is the one that goes stale. A
/// view gets the text; it never invents it.
///
/// Each note says three things: what runs, what leaves the device, and when to pick it. A mode that
/// is described only by its name is a mode chosen by guesswork.
public extension InferenceMode {
    var explainer: String {
        switch self {
        case .onDeviceOnly:
            return "Runs the whole answer on this iPhone — Apple's built-in model, or a model you "
                + "downloaded into Cairn. Nothing you type goes anywhere, and it keeps working with no "
                + "network at all. Choose it for privacy and for offline work. The on-device window is "
                + "small (roughly 4,096 tokens of prompt and answer together), so an older part of a long "
                + "conversation gets dropped to fit, and the largest models are out of reach."
        case .remoteOnly:
            return "Sends the prompt to the server you chose — Ollama, LM Studio, or anything "
                + "OpenAI-compatible — and shows you what that machine answers. Choose it for bigger "
                + "models, longer context, and a desktop or server GPU that answers faster than a phone "
                + "can. Your prompt leaves this device: to your own machine over your own network, or "
                + "through the public internet if that is the server you added, and Cairn keeps the "
                + "outbound badge up while it does."
        case .hybridParallel:
            return "Asks the on-device model and your remote server the same question at the same time, "
                + "then shows both answers side by side with their own timings and their own failures. "
                + "Nothing is merged and neither answer is rewritten, so you can compare them and keep "
                + "the one you trust. Choose it to see how much the server is really worth over the "
                + "phone. Both engines run, so the prompt still leaves the device once."
        case .hybridSynthesized:
            return "Asks both engines, then has one of them write a single answer from the two drafts — "
                + "so the reply in front of you carries both models' work instead of making you read two. "
                + "Choose it when you want one answer that takes the better parts of each. The two drafts, "
                + "which engine wrote the final text, and where each part came from are recorded on the "
                + "answer, so the merge can be checked rather than taken on trust."
        }
    }

    /// The mode's own name, for the `(i)` button's heading.
    var explainerTitle: String { displayName }

    /// One line, for the row that offers the mode.
    ///
    /// The menu is where the choice is actually made, and a list of four names is a list of four
    /// guesses. This is the part of `explainer` that decides the choice — who runs it, and whether a
    /// byte leaves — short enough to sit under the name without turning the menu into an essay. The
    /// full note stays one tap away on the `(i)` button.
    var shortNote: String {
        switch self {
        case .onDeviceOnly:
            return "Runs on this iPhone · nothing leaves it"
        case .remoteOnly:
            return "Your prompt goes to your server"
        case .hybridParallel:
            return "Both answer · you compare the two"
        case .hybridSynthesized:
            return "Both answer · one merged reply"
        }
    }
}