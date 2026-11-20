import CairnChatDomain
import Foundation

/// Why an on-device turn could not run, in terms the UI can show.
///
/// Each case is a distinct answer with a distinct fix. Collapsing them into "on-device model failed"
/// is what makes users toggle Apple Intelligence at random.
public enum OnDeviceGenerationError: String, Sendable, Error {
    case unavailable
    case unsupportedOS
    case frameworkAbsent
    case generationFailed
    case refused
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case inputTooLarge
    case cancelled

    public var message: String {
        switch self {
        case .unavailable: return "The on-device model is not available right now."
        case .unsupportedOS: return "On-device generation requires iOS 26 or later."
        case .frameworkAbsent: return "This build has no on-device model framework."
        case .generationFailed: return "On-device generation failed."
        case .refused: return "The on-device model declined to answer this request."
        case .deviceNotEligible:
            return "This iPhone cannot run Apple's on-device model. A server on your own network can "
                + "answer instead."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is switched off. Turn it on in Settings, or choose a server "
                + "under Servers."
        case .modelNotReady:
            return "Apple's on-device model is still preparing. Try again in a minute, or choose a "
                + "server under Servers."
        case .inputTooLarge:
            return "This turn does not fit the on-device model's context — it holds about 4,096 "
                + "tokens of prompt and answer together. Shorten the message, turn off Tools for this "
                + "turn, or choose a server with a bigger window."
        case .cancelled:
            return "The on-device answer was stopped."
        }
    }
}

/// So the reason reaches the person reading it.
///
/// A plain `Error` reaches `localizedDescription` as "(CairnInferenceLocal.OnDeviceGenerationError
/// error 3)" — a number in parentheses where a sentence should be, which is how a clear reason in the
/// code ends up as no reason at all on screen. The session writes `localizedDescription` into the
/// composer's error line, so this conformance is the whole distance between the two.
extension OnDeviceGenerationError: LocalizedError {
    public var errorDescription: String? { message }
}

/// What the framework actually complained about, in Cairn's words.
///
/// Matching is loose on purpose. The framework's error cases are not a stable surface this app should
/// hard-code against — a case renamed in a point release would turn a clear message back into
/// "generation failed" — so the framework's own text is read for what it is talking about and the
/// reason is mapped. Nothing here is logged: the text is inspected to choose a message, never stored,
/// because a framework description can carry part of the prompt it was given.
public enum OnDeviceFailure {
    public static func describe(_ underlying: any Error) -> OnDeviceGenerationError {
        if underlying is CancellationError { return .cancelled }
        let text = """
        \(String(describing: underlying))
        \(underlying.localizedDescription)
        """.lowercased()
        if text.contains("context window") || text.contains("context size")
            || text.contains("too long")
            || (text.contains("prompt") && text.contains("too")) {
            return .inputTooLarge
        }
        if text.contains("cancel") { return .cancelled }
        if text.contains("refus") || text.contains("declin") { return .refused }
        if text.contains("not available") || text.contains("unavailable") || text.contains("eligib") {
            return .unavailable
        }
        return .generationFailed
    }
}

public extension GenerationRequest {
    /// The system block, if the session put one first. Read, never synthesised: an encoder that
    /// invents a system prompt is the duplicate-system-message bug P2 closed.
    var systemText: String? {
        messages.first(where: { $0.role == .system })?.text
    }

    /// Everything that is not the system block, in order, as one prompt body.
    var conversationText: String {
        messages
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n\n")
    }
}
