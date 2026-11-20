import CairnChatDomain
import Foundation

/// One turn of a conversation, in the vocabulary an on-device runtime is handed.
///
/// Cairn's own payload carries images, tool-call blobs and call ids; a local template wants a role and
/// text. This type is the narrow bridge, and it exists so the deciding — which message becomes what —
/// can be read and tested on any host rather than only inside the file that imports the runtime.
struct NativeChatTurn: Sendable, Equatable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    var role: Role
    var text: String
}

/// Turns a `GenerationRequest` into the message list a local chat template expects.
enum MLXChatTranscript {
    /// The messages, in order, with nothing invented.
    ///
    /// A message with no text is dropped rather than rendered as an empty turn: an empty assistant turn
    /// is what a model reads as "continue from nothing", and an empty user turn is a question the user
    /// never asked. A payload that carries a call id is a **tool result**, whatever role it was stored
    /// under, because that is the only way Cairn marks one — and a tool answer shown as a user message
    /// teaches the model that users answer their own calls.
    static func turns(for request: GenerationRequest) -> [NativeChatTurn] {
        request.messages.compactMap { payload in
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if payload.toolCallID != nil {
                return NativeChatTurn(role: .tool, text: text)
            }
            switch payload.role {
            case .system: return NativeChatTurn(role: .system, text: text)
            case .user: return NativeChatTurn(role: .user, text: text)
            case .assistant: return NativeChatTurn(role: .assistant, text: text)
            }
        }
    }

    /// The system text for the runtime, taken from the same messages rather than from a second copy:
    /// two system blocks in one template is how a model ends up following the older one.
    static func systemText(for request: GenerationRequest) -> String? {
        let joined = request.messages
            .filter { $0.role == .system && $0.toolCallID == nil }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return joined.isEmpty ? nil : joined
    }
}
