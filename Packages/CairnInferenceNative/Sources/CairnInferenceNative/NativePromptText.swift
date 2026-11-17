import CairnChatDomain
import Foundation

/// Flattens a request into the prompt the native runtime is handed.
///
/// INTERNAL on purpose. `CairnInferenceLocal` exposes the same two reads publicly, and a second
/// public extension with the same member names would make an app that imports both modules
/// ambiguous. The rule is the same, so it is restated here narrowly rather than shared.
///
/// The system block is read, never synthesised: the session assembles exactly one, and an
/// encoder that prepends a second one is the duplicate-system-message bug P2 closed.
internal extension GenerationRequest {
    var nativeSystemText: String? {
        messages.first(where: { $0.role == .system })?.text
    }

    var nativePromptText: String {
        messages
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n\n")
    }
}
