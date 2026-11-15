import Foundation

/// Where a request actually goes. This is a privacy boundary, not a label:
/// `.publicInternet` requires explicit user opt-in and a persistent outbound badge.
public enum NetworkClass: String, Sendable, Equatable, Codable, CaseIterable {
    case onDevice
    /// RFC 1918, `.local`, or an unqualified host on the user's own LAN.
    case privateLan
    /// A Tailscale tailnet peer (100.64.0.0/10 or a `*.ts.net` MagicDNS name).
    /// Private, but NOT covered by `NSAllowsLocalNetworking`, so it is modelled
    /// separately from `.privateLan`.
    case tailnet
    case publicInternet

    public var leavesTheDevice: Bool {
        switch self {
        case .onDevice: return false
        case .privateLan, .tailnet, .publicInternet: return true
        }
    }

    public var requiresOptIn: Bool { self == .publicInternet }
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

    public init(
        id: String,
        displayName: String,
        providerID: String,
        parameterSize: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil,
        supportsVision: Bool = false,
        supportsThinking: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.contextLength = contextLength
        self.supportsVision = supportsVision
        self.supportsThinking = supportsThinking
    }
}

public struct ChatMessagePayload: Sendable, Equatable {
    public var role: ChatRole
    public var text: String
    /// Opaque attachment bytes; only ever handed to a vision-capable provider.
    public var imageData: [Data]

    public init(role: ChatRole, text: String, imageData: [Data] = []) {
        self.role = role
        self.text = text
        self.imageData = imageData
    }
}

public struct GenerationRequest: Sendable, Equatable {
    public var modelID: String
    /// Already flattened from the active root-to-leaf path of the tree.
    public var messages: [ChatMessagePayload]
    public var params: SamplingParams

    public init(modelID: String, messages: [ChatMessagePayload], params: SamplingParams) {
        self.modelID = modelID
        self.messages = messages
        self.params = params
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

    func models() async throws -> [ModelInfo]

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error>
}
