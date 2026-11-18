import Foundation

/// Where a request actually goes. This is a privacy boundary, not a label:
/// `.publicInternet` requires explicit user opt-in and a persistent outbound badge.
public enum NetworkClass: String, Sendable, Equatable, Codable, CaseIterable {
    case onDevice
    /// RFC 1918, `.local`, or an unqualified host on the user's own LAN.
    case privateLan
    /// A private peer reached **through a VPN** rather than over the local link: an
    /// address in the 100.64.0.0/10 block a mesh VPN allocates, a mesh-VPN DNS name, or a
    /// host inside a subnet a VPN gateway routes. Private, but not the LAN itself, so it
    /// is modelled separately from `.privateLan`. Cairn's own away-from-home route is not
    /// this class — the phone dials the server's LAN address through the router's
    /// WireGuard tunnel, which `.privateLan` already covers — so the class exists to keep
    /// VPN addresses honestly labelled, not to require any particular VPN product.
    case privateVPN
    case publicInternet

    public var leavesTheDevice: Bool {
        switch self {
        case .onDevice: return false
        case .privateLan, .privateVPN, .publicInternet: return true
        }
    }

    public var requiresOptIn: Bool { self == .publicInternet }

    /// May this server be reached over plaintext http?
    ///
    /// Yes for anything private. A LAN segment carries only the user's own traffic,
    /// and a VPN tunnel (WireGuard) encrypts the path itself, so transport security
    /// lives below HTTP rather than inside it. No for a public-internet host, which
    /// has no such protected path.
    ///
    /// Apple's own ATS scope is what makes this reachable with no exception: ATS
    /// "applies only to connections made to public host names", and the system "does
    /// not provide ATS protection to connections made to: Internet protocol (IP)
    /// addresses, Unqualified host names, Local hosts employing the .local top-level
    /// domain" (Cocoa Keys, *Availability of ATS for Remote and Local Connections*).
    /// `NSAllowsLocalNetworking` is still declared in the app's Info.plist, because
    /// ATS *does* apply to an unqualified or `.local` **name** — and Apple states that
    /// key makes ATS ignore `NSAllowsArbitraryLoads` entirely, so adding it narrows
    /// the app's ATS posture rather than widening it.
    public var allowsPlaintext: Bool { self != .publicInternet }
}

/// What a given server or runtime can actually do. The UI derives every button
/// from these flags, so an OpenAI-compatible server never shows "Pull model"
/// or "Loaded models" just because another server supports them.
public struct ProviderCapabilities: Sendable, Equatable {
    public var streaming: Bool
    public var thinking: Bool
    public var toolCalling: Bool
    public var vision: Bool
    public var modelListing: Bool
    public var modelPull: Bool
    public var modelDelete: Bool
    public var loadedModelInspection: Bool
    public var contextLengthAdjustable: Bool

    public init(
        streaming: Bool = true,
        thinking: Bool = false,
        toolCalling: Bool = false,
        vision: Bool = false,
        modelListing: Bool = true,
        modelPull: Bool = false,
        modelDelete: Bool = false,
        loadedModelInspection: Bool = false,
        contextLengthAdjustable: Bool = true
    ) {
        self.streaming = streaming
        self.thinking = thinking
        self.toolCalling = toolCalling
        self.vision = vision
        self.modelListing = modelListing
        self.modelPull = modelPull
        self.modelDelete = modelDelete
        self.loadedModelInspection = loadedModelInspection
        self.contextLengthAdjustable = contextLengthAdjustable
    }

    public static let ollama = ProviderCapabilities(
        streaming: true,
        thinking: true,
        toolCalling: true,
        vision: true,
        modelListing: true,
        modelPull: true,
        modelDelete: true,
        loadedModelInspection: true
    )

    public static let openAICompatible = ProviderCapabilities(
        streaming: true,
        thinking: false,
        toolCalling: true,
        vision: false,
        modelListing: true,
        modelPull: false,
        modelDelete: false,
        loadedModelInspection: false
    )

    public static let onDevice = ProviderCapabilities(
        streaming: true,
        thinking: false,
        toolCalling: false,
        vision: false,
        modelListing: true,
        modelPull: false,
        modelDelete: false,
        loadedModelInspection: false,
        contextLengthAdjustable: false
    )
}

public struct ModelInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var providerID: String
    public var parameterSize: String?
    public var quantization: String?
    public var contextLength: Int?
    public var supportsVision: Bool
    public var supportsThinking: Bool
    /// Published by the server, never inferred from a model's name or size. A catalog entry that
    /// states nothing keeps `false`, which is why a tool turn's format comes from the server kind's
    /// declared capabilities and this flag only ever **adds** a badge the server itself claimed.
    public var supportsTools: Bool

    public init(
        id: String,
        displayName: String,
        providerID: String,
        parameterSize: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil,
        supportsVision: Bool = false,
        supportsThinking: Bool = false,
        supportsTools: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.contextLength = contextLength
        self.supportsVision = supportsVision
        self.supportsThinking = supportsThinking
        self.supportsTools = supportsTools
    }
}

public struct ChatMessagePayload: Sendable, Equatable {
    public var role: ChatRole
    public var text: String
    /// Opaque attachment bytes; only ever handed to a vision-capable provider.
    public var imageData: [Data]
    /// Calls this assistant turn asked for, so a native backend can be shown its own turn with the
    /// calls still attached. Empty on every message written before P3, and on every turn with no
    /// tools — the field's absence is what keeps an old conversation byte-identical on the wire.
    public var toolCalls: [ToolCallRequest]
    /// Set on a **tool result** payload: the call this text answers. The encoder sends such a payload
    /// with the dialect's tool role rather than as ordinary user text, which is why the role stays a
    /// plain `ChatRole` and no `tool` case is invented — a new role would ripple through every stored
    /// message for something only one kind of message needs.
    public var toolCallID: String?

    public init(
        role: ChatRole,
        text: String,
        imageData: [Data] = [],
        toolCalls: [ToolCallRequest] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.text = text
        self.imageData = imageData
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    /// A tool result, which is the only payload that carries an id to match against.
    public static func toolResult(callID: String, text: String) -> ChatMessagePayload {
        ChatMessagePayload(role: .user, text: text, toolCallID: callID)
    }

    /// Whether this payload is a tool result rather than something the user or the model said.
    public var isToolResult: Bool { toolCallID != nil }
}


public struct GenerationRequest: Sendable, Equatable {
    public var modelID: String
    /// Flattened from the active root-to-leaf path of the tree. When there is a system message it is
    /// the **first element and the only one**: the block is assembled once by
    /// `ChatConfig.systemPrompt(in:turn:)` in the session, and an encoder must never add a second
    /// one. Two places each prepending a system prompt is the duplicate-system-message bug P2 closes.
    public var messages: [ChatMessagePayload]
    /// The chat's own configuration, so an encoder can apply the server's capability filter itself.
    public var config: ChatConfig
    /// The tools this turn offers, already narrowed by the user's switches and the context budget.
    /// Empty on every turn with the `Tools` chip down, which is what keeps a tools-off request free
    /// of tool vocabulary on the wire as well as in the prompt.
    public var tools: [ToolDefinition]
    /// How a call would travel on this turn, so an encoder knows whether to emit a `tools` array and
    /// read structured calls back, or to say nothing about tools at all and let the prompt protocol
    /// do the work.
    public var toolProtocol: ToolCallingProtocol

    public init(
        modelID: String,
        messages: [ChatMessagePayload],
        config: ChatConfig,
        tools: [ToolDefinition] = [],
        toolProtocol: ToolCallingProtocol = .none
    ) {
        self.modelID = modelID
        self.messages = messages
        self.config = config
        self.tools = tools
        self.toolProtocol = toolProtocol
    }

    public var promptCharacterCount: Int {
        messages.reduce(0) { $0 + $1.text.count }
    }
}

/// One protocol for every backend: on-device runtime, LAN server, or cloud.
public protocol InferenceProvider: Sendable, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var networkClass: NetworkClass { get }
    var capabilities: ProviderCapabilities { get }
    /// The sampling knobs this engine will actually read. The configuration sheet renders from this
    /// table and the encoder filters with the same table, so a knob can never appear in the UI that
    /// the outbound request would then drop — a silently ignored knob is one the user believes works.
    var samplingSupport: SamplingSupport { get }
    /// The saved server profile this engine was built from, when it was built from one. The
    /// server switcher needs it to map an engine back to the profile whose last model it should
    /// restore; a mock or on-device engine has none and takes the default in `RemoteEngineID`.
    var serverProfileID: UUID? { get }

    func models() async throws -> [ModelInfo]

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error>
}

/// An engine that says nothing about sampling takes nothing. The default is deliberately the empty
/// set: offering a slider an engine has not been observed to read is the failure this table exists
/// to prevent, so support is declared rather than assumed.
public extension InferenceProvider {
    var samplingSupport: SamplingSupport { .none }
}
