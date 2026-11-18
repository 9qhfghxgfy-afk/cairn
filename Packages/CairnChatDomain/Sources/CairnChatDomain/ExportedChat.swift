import Foundation

/// The on-disk shape of one conversation inside a `.cairn` file.
///
/// Raw strings for the enum-valued fields are deliberate. A file from a future build that adds a mode
/// this one has never heard of must be **refused**, not decoded into the nearest guess — a chat opened
/// under the wrong mode would send prompts somewhere the user did not choose. `ChatImport` checks these
/// strings and names what it could not read.
///
/// There is no `isTemporary` field, and that is a rule rather than an omission: a file the user saved is
/// a durable record, so an imported chat is always a saved chat, and nothing an import writes can be
/// mistaken for a chat that was supposed to die with the process.
public struct ExportedChat: Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var activeLeafID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var mode: String
    public var config: ChatConfig

    public init(
        id: UUID,
        title: String,
        activeLeafID: UUID?,
        createdAt: Date,
        updatedAt: Date,
        mode: String,
        config: ChatConfig
    ) {
        self.id = id
        self.title = title
        self.activeLeafID = activeLeafID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.config = config
    }

    public init(_ conversation: Conversation) {
        self.init(
            id: conversation.id,
            title: conversation.title,
            activeLeafID: conversation.activeLeafID,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            mode: conversation.mode.rawValue,
            config: conversation.config
        )
    }

    /// nil when this build cannot read the mode the file names — the refusal the header of this type
    /// exists to make possible.
    public func toConversation() -> Conversation? {
        guard let inferenceMode = InferenceMode(rawValue: mode) else { return nil }
        return Conversation(
            id: id,
            title: title,
            activeLeafID: activeLeafID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mode: inferenceMode,
            config: config,
            isTemporary: false
        )
    }
}
