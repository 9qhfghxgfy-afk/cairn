import Foundation

/// Everything a single chat knows about how it should answer.
///
/// Three parts, and they behave differently:
/// - `persona` is the user's own system prompt, sent verbatim at the head of the injected block.
/// - `sampling` holds the knobs, each of which is **unset or configured** — unset means the key is
///   left out of the request so the server's default stands.
/// - `context` decides which facts Cairn adds around the persona, and the response shape.
///
/// A chat is seeded from the Default Configuration in Settings when it is created, and can then be
/// overridden or reset. Defaults are copied, not layered: quietly re-resolving an old chat against
/// settings the user changed since would rewrite a conversation's behaviour behind their back.
public struct ChatConfig: Sendable, Equatable, Codable {
    public var persona: String
    public var sampling: SamplingConfig
    public var context: ContextToggleSet
    public var responseFormat: ResponseFormatPreference
    public var thinkingEnabled: Bool
    /// Which engines answer a hybrid turn and which one writes the unified answer.
    ///
    /// Optional on purpose: a chat written before M4 has no key for this and decodes to `nil`,
    /// which means "choose from the engines registered now" rather than a plan invented from
    /// nothing. It lives here because this is already one configuration blob per chat, so a
    /// fourth picker never becomes a schema migration.
    public var hybrid: HybridPlan?

    public init(
        persona: String = "",
        sampling: SamplingConfig = .unset,
        context: ContextToggleSet = .default,
        responseFormat: ResponseFormatPreference = .markdown,
        thinkingEnabled: Bool = false,
        hybrid: HybridPlan? = nil
    ) {
        self.persona = persona
        self.sampling = sampling
        self.context = context
        self.responseFormat = responseFormat
        self.thinkingEnabled = thinkingEnabled
        self.hybrid = hybrid
    }

    /// A new chat: no sampling knobs asserted, the default injections on, answers in Markdown.
    public static let `default` = ChatConfig()

    /// Nothing injected and nothing asserted — the shape a user reaches for by turning everything
    /// off, and the shape a test wants when it needs "exactly the persona, nothing else".
    public static let bare = ChatConfig(context: .off)

    /// The number behind the "N options configured" badge: sampling knobs the chat explicitly
    /// asserts. The persona and the injection toggles are not counted — a chat with no knobs set is
    /// not a chat with nothing configured, but it *is* a chat that asks nothing of the server.
    public var configuredOptionCount: Int { sampling.configuredOptionCount }

    /// The exact system block for one turn — the text the live preview shows and the text that goes
    /// on the wire, from this one call.
    public func systemPrompt(
        in environment: ContextEnvironment,
        turn: TurnContext = .default
    ) -> String {
        ContextAssembly.assemble(
            persona: persona,
            toggles: context,
            format: responseFormat,
            environment: environment,
            turn: turn
        )
    }

    public func blocks(
        in environment: ContextEnvironment,
        turn: TurnContext = .default
    ) -> [String] {
        ContextAssembly.blocks(
            persona: persona,
            toggles: context,
            format: responseFormat,
            environment: environment,
            turn: turn
        )
    }

    /// "Reset to Defaults": this chat ends up holding exactly the given baseline, so a knob the
    /// baseline leaves unset is unset here too rather than keeping its old value.
    public mutating func reset(to defaults: ChatConfig) {
        self = defaults
    }

    /// Knobs this chat asserts that the active server cannot honour — the set the sheet warns
    /// about, because a silently ignored key is a knob the user believes is working.
    public func unsupportedKeys(for support: SamplingSupport) -> [SamplingKey] {
        support.droppedKeys(from: sampling)
    }
}
