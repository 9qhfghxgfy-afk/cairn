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
