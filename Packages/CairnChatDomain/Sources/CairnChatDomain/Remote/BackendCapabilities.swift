import Foundation

extension ProviderCapabilities {
    /// LM Studio serves the OpenAI-compatible chat surface, so streaming and tool calling come
    /// from that dialect. Thinking is `false` because no reasoning field has been observed from
    /// this machine, and the rule is that a reasoning panel appears only for a backend proven to
    /// emit one — never for a kind that might.
    public static let lmStudio = ProviderCapabilities(
        streaming: true,
        thinking: false,
        toolCalling: true,
        vision: false,
        modelListing: true,
        modelPull: false,
        modelDelete: false,
        loadedModelInspection: false
    )

    /// Ollama's hosted API: chat and listing only. Ollama's own docs state that creating or
    /// deleting models requires a local server, so the cloud kind declares neither.
    public static let ollamaCloud = ProviderCapabilities(
        streaming: true,
        thinking: false,
        toolCalling: false,
        vision: false,
        modelListing: true,
        modelPull: false,
        modelDelete: false,
        loadedModelInspection: false
    )
}

/// The paths one server kind uses, relative to the profile's canonical base URL.
public struct ServerEndpoints: Sendable, Equatable {
    public var chat: String
    public var models: String
    /// nil means the dialect has no such endpoint, so no UI may offer the action.
    public var load: String?
    public var unload: String?
    public var download: String?
    /// Where a server reports what it currently holds in memory. nil means no such surface, so
    /// the Running tab offers nothing for this kind rather than an empty list.
    public var running: String?
    /// Where a server publishes one model's own metadata. nil means the Installed tab shows the
    /// list entry only, rather than inventing a detail panel.
    public var show: String?
    /// True only once this build actually issues the lifecycle calls. LM Studio's native
    /// load / unload / download paths are declared in P1 and wired in M3, so until this flag
    /// flips no screen may offer them — a declared endpoint is not a working one.
    public var lifecycleWired: Bool

    public init(
        chat: String,
        models: String,
        load: String? = nil,
        unload: String? = nil,
        download: String? = nil,
        running: String? = nil,
        show: String? = nil,
        lifecycleWired: Bool = true
    ) {
        self.chat = chat
        self.models = models
        self.load = load
        self.unload = unload
        self.download = download
        self.running = running
        self.show = show
        self.lifecycleWired = lifecycleWired
    }

    /// Every path this kind declares. `ServerKindBackendTests` walks it to prove no legacy
    /// LM Studio v0 surface is coded against, and that each path is absolute.
    public var declaredPaths: [String] {
        [chat, models, load, unload, download, running, show].compactMap { $0 }
    }
}
