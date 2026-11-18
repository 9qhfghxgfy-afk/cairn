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
            // The pre-P2 column is left empty for new rows; the configuration is one blob now.
            paramsJSON: Data(),
            configJSON: JSONCodec.encode(conversation.config)
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
            config: readConfig(),
            // Nothing on disk is ever temporary.
            isTemporary: false
        )
    }

    /// The chat's configuration, or the configuration reconstructed from the pre-P2 knob blob.
    ///
    /// A row written before P2 has `paramsJSON` and no `configJSON`. Those knobs were all mandatory,
    /// so every one of them was asserted on every turn — reading them back as *configured* overrides
    /// is what keeps an existing chat answering the same way after the upgrade, instead of quietly
    /// falling back to server defaults.
    private func readConfig() -> ChatConfig {
        if let stored = JSONCodec.decode(ChatConfig.self, from: configJSON) {
            return stored
        }
        return LegacyChatConfig.upgrade(from: paramsJSON)
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
            // nil stays nil rather than storing a "null" blob.
            metricsJSON: node.metrics.flatMap { JSONCodec.encode($0) },
            provenanceJSON: node.provenance.flatMap { JSONCodec.encode($0) },
            toolRunJSON: node.toolRun.flatMap { JSONCodec.encode($0) },
            toolsOfferedJSON: JSONCodec.encodeIfNotEmpty(node.toolsOffered)
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
            metrics: JSONCodec.decode(GenerationMetrics.self, from: metricsJSON),
            // A node written before M4 has no provenance column, and a non-hybrid node never
            // writes one: both read back as nil, which is what they are.
            provenance: JSONCodec.decode(HybridProvenance.self, from: provenanceJSON),
            // A node with no tool column is a node from before P3, or a turn that ran no tool: both
            // read as "no calls", never as an empty call record the UI would render as a card.
            toolsOffered: JSONCodec.decode([String].self, from: toolsOfferedJSON) ?? [],
            toolRun: JSONCodec.decode(ToolRun.self, from: toolRunJSON)
        )
    }
}
