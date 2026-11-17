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

    public var message: String {
        switch self {
        case .unavailable: return "The on-device model is not available right now."
        case .unsupportedOS: return "On-device generation requires iOS 26 or later."
        case .frameworkAbsent: return "This build has no on-device model framework."
        case .generationFailed: return "On-device generation failed."
        case .refused: return "The on-device model declined to answer this request."
        }
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
