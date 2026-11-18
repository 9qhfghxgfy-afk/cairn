import Foundation

/// What this turn can actually do, and what is attached to it. This is what decides whether a
/// conditional block is worth writing: a reminder about tools on a turn with no tools teaches the
/// model to pretend.
///
/// Nothing here identifies the user. `backendLabel` describes a class of backend ("a server on your
/// own network"), never the profile's name or address — those are the user's, and they do not
/// belong in a prompt the user did not explicitly choose to write.
public struct TurnContext: Sendable, Equatable {
    /// A plain-language description of where this turn is going, or nil when it has not been
    /// resolved yet — an unknown backend gets no capability line rather than a wrong one.
    public var backendLabel: String?
    public var onDevice: Bool
    public var streaming: Bool
    public var thinkingOn: Bool
    public var toolsActive: Bool
    public var toolNames: [String]
    public var webFetchActive: Bool
    public var visionOn: Bool
    public var fileCount: Int
    public var imageCount: Int
    /// Passages Cairn read out of the attached documents for this turn, numbered as they are numbered
    /// in the block. Empty on every turn with no documents, and on every turn whose documents did not
    /// answer the question — in both cases the file block says what was attached and nothing more.
    public var passages: [RetrievedPassage]
    /// Only a context size the user actually configured; the server's own is not Cairn's to state.
    public var contextTokens: Int?

    public init(
        backendLabel: String? = nil,
        onDevice: Bool = false,
        streaming: Bool = true,
        thinkingOn: Bool = false,
        toolsActive: Bool = false,
        toolNames: [String] = [],
        webFetchActive: Bool = false,
        visionOn: Bool = false,
        fileCount: Int = 0,
        imageCount: Int = 0,
        passages: [RetrievedPassage] = [],
        contextTokens: Int? = nil
    ) {
        self.backendLabel = backendLabel
        self.onDevice = onDevice
        self.streaming = streaming
        self.thinkingOn = thinkingOn
        self.toolsActive = toolsActive
        self.toolNames = toolNames
        self.webFetchActive = webFetchActive
        self.visionOn = visionOn
        self.fileCount = fileCount
        self.imageCount = imageCount
        self.passages = passages
        self.contextTokens = contextTokens
    }

    /// A plain text-only turn against an unresolved backend: the shape the app has when tools
    /// (P3) and attachments (M6) do not exist yet.
    public static let `default` = TurnContext()

    /// A turn on the phone, which is the one case where "nothing left the device" is worth telling
    /// the model, because it changes what the model offers to do.
    public static var onDeviceOnly: TurnContext {
        TurnContext(
            backendLabel: "a model running on this device, so nothing here reaches a server",
            onDevice: true
        )
    }
}
