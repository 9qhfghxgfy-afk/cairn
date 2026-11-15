import Foundation
import CairnChatDomain

enum JSONCodec {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return data
    }

    static func encodeIfNotEmpty<T: Encodable>(_ value: [T]) -> Data? {
        guard !value.isEmpty else { return nil }
        return encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension ConversationRecord {
    convenience init(_ conversation: Conversation) {
        self.init(
            id: conversation.id,
            title: conversation.title,
            activeLeafID: conversation.activeLeafID,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            modeRaw: conversation.mode.rawValue,
            paramsJSON: JSONCodec.encode(conversation.params) ?? Data()
        )
    }

    func toConversation() -> Conversation {
        Conversation(
            id: id,
            title: title,
            activeLeafID: activeLeafID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mode: InferenceMode(rawValue: modeRaw) ?? .onDeviceOnly,
            params: JSONCodec.decode(SamplingParams.self, from: paramsJSON) ?? .default,
            // Nothing on disk is ever temporary.
            isTemporary: false
        )
    }
}

extension ChatRecord {
    convenience init(_ node: ChatNode) {
        self.init(
            id: node.id,
            conversationID: node.conversationID,
            parentID: node.parentID,
            roleRaw: node.role.rawValue,
            kindRaw: node.kind.rawValue,
            stateRaw: node.state.rawValue,
            text: node.text,
            thinking: node.thinking,
            branchIndex: node.branchIndex,
            providerID: node.providerID,
            modelID: node.modelID,
            createdAt: node.createdAt,
            draftsJSON: JSONCodec.encodeIfNotEmpty(node.drafts),
            metricsJSON: JSONCodec.encode(node.metrics)
        )
    }

    func toNode() -> ChatNode {
        ChatNode(
            id: id,
            conversationID: conversationID,
            parentID: parentID,
            role: ChatRole(rawValue: roleRaw) ?? .user,
            kind: NodeKind(rawValue: kindRaw) ?? .plain,
            text: text,
            thinking: thinking,
            state: NodeState(rawValue: stateRaw) ?? .complete,
            branchIndex: branchIndex,
            providerID: providerID,
            modelID: modelID,
            createdAt: createdAt,
            drafts: JSONCodec.decode([CandidateDraft].self, from: draftsJSON) ?? [],
            metrics: JSONCodec.decode(GenerationMetrics.self, from: metricsJSON)
        )
    }
}
