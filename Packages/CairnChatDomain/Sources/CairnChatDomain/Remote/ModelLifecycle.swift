import Foundation

/// What a server says is loaded in its own memory right now.
///
/// Every field is read from the server's own reply. A size the server did not report stays `nil`
/// rather than being estimated, because the Running tab shows these numbers as facts.
public struct ResidentServerModel: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var serverName: String
    /// Total bytes held, as reported by the server.
    public var memoryBytes: Int64?
    /// The share held on the GPU, when the server separates it.
    public var vramBytes: Int64?
    /// When the server will evict this by itself. `nil` means it never said, not that it never will.
    public var expiresAt: Date?
    public var contextLength: Int?

    public init(
        id: String,
        displayName: String,
        serverName: String,
        memoryBytes: Int64? = nil,
        vramBytes: Int64? = nil,
        expiresAt: Date? = nil,
        contextLength: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.serverName = serverName
        self.memoryBytes = memoryBytes
        self.vramBytes = vramBytes
        self.expiresAt = expiresAt
        self.contextLength = contextLength
    }
}

/// What a server publishes about one model. Read from `/api/show` or an equivalent detail
/// endpoint; nothing here is inferred from a model's name or size.
public struct ModelDetail: Sendable, Equatable {
    public var id: String
    public var parameterSize: String?
    public var quantization: String?
    public var contextLength: Int?
    /// Published capability flags only. A server that states nothing yields no badge — a guessed
    /// badge is a claim the user will act on.
    public var supportsVision: Bool
    public var supportsTools: Bool
    public var supportsThinking: Bool
    /// Free text the server itself published (license note, family). Shown as returned.
    public var publishedNote: String?

    public init(
        id: String,
        parameterSize: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil,
        supportsVision: Bool = false,
        supportsTools: Bool = false,
        supportsThinking: Bool = false,
        publishedNote: String? = nil
    ) {
        self.id = id
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.contextLength = contextLength
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
        self.supportsThinking = supportsThinking
        self.publishedNote = publishedNote
    }

    public var capabilityLabels: [String] {
        var labels: [String] = []
        if supportsVision { labels.append("Vision") }
        if supportsTools { labels.append("Tools") }
        if supportsThinking { labels.append("Thinking") }
        return labels
    }
}

/// One line of a streaming model download, as the server reported it.
public struct ModelPullProgress: Sendable, Equatable {
    public var modelName: String
    /// The server's own status text, shown as written. Cairn does not rewrite it, because a
    /// paraphrased progress line is a claim about someone else's server.
    public var statusText: String
    public var completedBytes: Int64?
    public var totalBytes: Int64?

    public init(
        modelName: String,
        statusText: String,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        self.modelName = modelName
        self.statusText = statusText
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    /// nil when the server never named a total. A guessed denominator would misreport how close
    /// a download is, which is the one thing a progress bar must not do.
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0, let completedBytes else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}
