import Foundation

/// A conversation, which is a title plus one pointer.
///
/// `activeLeafID` is the only thing that decides what the user sees. There is no message array here
/// on purpose: order lives in parent pointers, so appending a branch never rewrites anything.
public struct Conversation: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    /// The only pointer deciding what the user sees.
    public var activeLeafID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var mode: InferenceMode
    /// This chat's own configuration: persona, sampling overrides, injected context.
    public var config: ChatConfig
    /// In-memory only when true: never written to disk by any store.
    public var isTemporary: Bool

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        activeLeafID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: InferenceMode = .onDeviceOnly,
        config: ChatConfig = .default,
        isTemporary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.activeLeafID = activeLeafID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.config = config
        self.isTemporary = isTemporary
    }
}
