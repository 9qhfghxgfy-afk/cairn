import Foundation

/// One kind's whole declared surface: what it can do, where it does it, and how the Add-server
/// form should prefill it. Pure data, so a host test can assert the map with no server at all.
public struct ServerBackend: Sendable, Equatable {
    public var capabilities: ProviderCapabilities
    public var endpoints: ServerEndpoints
    /// The port this kind listens on by default, for the guide and the scan hint.
    public var defaultPort: Int?
    /// What the URL field starts with. A LAN box is prefilled with the scheme only — the user's
    /// own address is never guessed here, and no real address belongs in this file anyway.
    public var prefilledURL: String
    public var prefilledName: String
    /// A Keychain token is expected rather than optional: this server refuses requests without one.
    public var expectsToken: Bool
    /// Inert until the user turns it on. Used for the cloud kind, which is never a surprise.
    public var offByDefault: Bool

    public init(
        capabilities: ProviderCapabilities,
        endpoints: ServerEndpoints,
        defaultPort: Int? = nil,
        prefilledURL: String = "http://",
        prefilledName: String = "",
        expectsToken: Bool = false,
        offByDefault: Bool = false
    ) {
        self.capabilities = capabilities
        self.endpoints = endpoints
        self.defaultPort = defaultPort
        self.prefilledURL = prefilledURL
        self.prefilledName = prefilledName
        self.expectsToken = expectsToken
        self.offByDefault = offByDefault
    }

    public static func backend(for kind: ServerProfileKind) -> ServerBackend {
        switch kind {
        case .ollama:
            return ServerBackend(
                capabilities: .ollama,
                endpoints: ServerEndpoints(chat: "/api/chat", models: "/api/tags"),
                defaultPort: 11434
            )
        case .lmStudio:
            // Native REST for the model list and the lifecycle, OpenAI-compatible for the chat
            // stream. `lifecycleWired: false` is the M3 gate: the paths are declared now so the
            // calls land against the right endpoint, and no screen offers them before they exist.
            return ServerBackend(
                capabilities: .lmStudio,
                endpoints: ServerEndpoints(
                    chat: "/v1/chat/completions",
                    models: "/api/v1/models",
                    load: "/api/v1/models/load",
                    unload: "/api/v1/models/unload",
                    download: "/api/v1/models/download",
                    lifecycleWired: false
                ),
                defaultPort: 1234
            )
        case .openAICompatible:
            return ServerBackend(
                capabilities: .openAICompatible,
                endpoints: ServerEndpoints(chat: "/v1/chat/completions", models: "/v1/models")
            )
        case .ollamaCloud:
            // `https://ollama.com` carries both documented cloud surfaces: `/api/*` and `/v1/*`.
            // The base URL holds no path, so the request builder can address either.
            return ServerBackend(
                capabilities: .ollamaCloud,
                endpoints: ServerEndpoints(chat: "/api/chat", models: "/api/tags"),
                prefilledURL: "https://ollama.com",
                prefilledName: "Ollama Cloud",
                expectsToken: true,
                offByDefault: true
            )
        }
    }

    /// The host a cloud kind must point at. Any other host is a different server and belongs to
    /// another kind, because the kind name would then describe something the profile is not.
    public static let cloudHost = "ollama.com"
}
