import Foundation

/// Why a turn body could not be used. Typed, and it never carries the body.
public enum ShareRequestFailure: String, Sendable, Equatable, Error {
    case undecodable
    case missingModel
    case emptyMessages
    case unknownModel
}

/// One turn a client asked this phone to run.
public struct ShareTurnRequest: Sendable, Equatable {
    /// The served name — which **is** an engine id, so this is also the id the engine is asked with.
    public var modelID: String
    public var messages: [ChatMessagePayload]
    public var streams: Bool
    public var sampling: SamplingConfig
    /// A client asked for reasoning. Nothing here makes a model reason: the flag only says the
    /// engine may be asked, and the reasoning panel still appears only if the engine really emits it.
    public var thinkingRequested: Bool
    public var endpoint: ShareEndpoint

    public init(
        modelID: String,
        messages: [ChatMessagePayload],
        streams: Bool,
        sampling: SamplingConfig = .unset,
        thinkingRequested: Bool = false,
        endpoint: ShareEndpoint
    ) {
        self.modelID = modelID
        self.messages = messages
        self.streams = streams
        self.sampling = sampling
        self.thinkingRequested = thinkingRequested
        self.endpoint = endpoint
    }

    /// The request to hand to the engine.
    ///
    /// `context: .off` because the text arrived already assembled by whoever called: injecting
    /// Cairn's own environment block into somebody else's prompt would be answering a question
    /// that was never asked of Cairn. No tools are offered either — a shared surface forwards a
    /// turn, it does not arm a stranger's conversation with this phone's tools.
    public func generationRequest() -> GenerationRequest {
        GenerationRequest(
            modelID: modelID,
            messages: messages,
            config: ChatConfig(
                persona: "",
                sampling: sampling,
                context: .off,
                thinkingEnabled: thinkingRequested
            )
        )
    }
}

/// Reads a turn body in either dialect.
///
/// One important default: **Ollama streams unless told not to, OpenAI does not stream unless told
/// to.** Getting that backwards is the kind of bug that looks like the model is broken, because
/// the client is left reading a body the server wrote in the other mode.
public enum ShareTurnDecoder {
    public static func decode(body: Data, endpoint: ShareEndpoint) -> Result<ShareTurnRequest, ShareRequestFailure> {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: body),
              let object = root.dictionaryValue
        else { return .failure(.undecodable) }

        let dialect = endpoint.dialect ?? .ollama
        guard let model = object["model"]?.textValue, !model.isEmpty else {
            return .failure(.missingModel)
        }
        let messages = messagesFrom(object["messages"]) ?? messagesFromPrompt(object["prompt"])
        guard !messages.isEmpty else { return .failure(.emptyMessages) }

        return .success(
            ShareTurnRequest(
                modelID: model,
                messages: messages,
                streams: streamsFlag(object["stream"], dialect: dialect),
                sampling: ShareTurnSampling.read(object, dialect: dialect),
                thinkingRequested: ShareTurnSampling.thinkingRequested(object, dialect: dialect),
                endpoint: endpoint
            )
        )
    }

    /// Default per dialect, honouring an explicit value in either direction.
    static func streamsFlag(_ value: JSONValue?, dialect: ShareDialect) -> Bool {
        guard let explicit = value?.boolValue else { return dialect == .ollama }
        return explicit
    }

    /// `messages` as the client sent them. A `content` may be a string or a list of parts, which is
    /// what a multimodal client sends; the text parts are joined and nothing else is interpreted.
    static func messagesFrom(_ value: JSONValue?) -> [ChatMessagePayload]? {
        guard let entries = value?.arrayValue, !entries.isEmpty else { return nil }
        var payloads: [ChatMessagePayload] = []
        for entry in entries {
            guard let object = entry.dictionaryValue else { continue }
            let role = ChatRole(rawValue: object["role"]?.textValue ?? "") ?? .user
            let text = textOf(object["content"])
            if text.isEmpty, object["content"] == nil { continue }
            payloads.append(ChatMessagePayload(role: role, text: text))
        }
        return payloads.isEmpty ? nil : payloads
    }

    /// The completion-shaped bodies (`/api/generate`, `/v1/completions`) carry one prompt instead
    /// of a message list, so they become one user turn.
    static func messagesFromPrompt(_ value: JSONValue?) -> [ChatMessagePayload] {
        guard let value else { return [] }
        let text = textOf(value)
        return text.isEmpty ? [] : [ChatMessagePayload(role: .user, text: text)]
    }

    static func textOf(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if let text = value.textValue { return text }
        if let parts = value.arrayValue {
            return parts.compactMap { part in
                if let text = part.textValue { return text }
                return part.dictionaryValue?["text"]?.textValue
            }.joined()
        }
        return ""
    }
}
