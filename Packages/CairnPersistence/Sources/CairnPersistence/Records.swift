import Foundation
import SwiftData
import CairnChatDomain

/// On-disk shape of a conversation. Temporary chats never reach this file at all —
/// they are backed by `EphemeralStore`, and `SwiftDataStore` refuses them outright.
@Model
public final class ConversationRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    /// The only pointer deciding what the user sees.
    public var activeLeafID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var modeRaw: String
    public var paramsJSON: Data
    /// The whole per-chat configuration, as a `ChatConfig` JSON blob.
    ///
    /// One blob rather than a column per knob: the knobs are read and written as a single value, and a
    /// column per knob makes every later knob a migration. `ChatConfig` holds no URL, hostname, or
    /// credential, so this column cannot become a place a private address gets stored by accident.
    ///
    /// `paramsJSON` above is the pre-P2 column and is no longer written. It is kept because dropping a
    /// column from a store the user already has on disk is the one schema change that is not free, and
    /// because a row written before P2 still has to be read.
    public var configJSON: Data?

    public init(
        id: UUID,
        title: String,
        activeLeafID: UUID?,
        createdAt: Date,
        updatedAt: Date,
        modeRaw: String,
        paramsJSON: Data,
        configJSON: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.activeLeafID = activeLeafID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modeRaw = modeRaw
        self.paramsJSON = paramsJSON
        self.configJSON = configJSON
    }
}

/// A chat node stored as a PARENT POINTER, not an ordered array. Edit, regenerate,
/// and branch append rows here and only repoint `ConversationRecord.activeLeafID`.
@Model
public final class ChatRecord {
    @Attribute(.unique) public var id: UUID
    public var conversationID: UUID
    public var parentID: UUID?
    public var roleRaw: String
    public var kindRaw: String
    public var stateRaw: String
    public var text: String
    /// Non-nil only when a backend really emitted reasoning.
    public var thinking: String?
    public var branchIndex: Int
    public var providerID: String?
    public var modelID: String?
    public var createdAt: Date
    /// Candidate drafts of a hybrid turn, kept inside the one node.
    public var draftsJSON: Data?
    public var metricsJSON: Data?
    /// How a hybrid turn was produced — `HybridProvenance` as JSON. Its own column because it is
    /// one value read whole, and because a column per field would make every later field of
    /// provenance a schema migration. Counts and engine/model ids only: never prompt or answer text.
    public var provenanceJSON: Data?

    public init(
        id: UUID,
        conversationID: UUID,
        parentID: UUID?,
        roleRaw: String,
        kindRaw: String,
        stateRaw: String,
        text: String,
        thinking: String?,
        branchIndex: Int,
        providerID: String?,
        modelID: String?,
        createdAt: Date,
        draftsJSON: Data?,
        metricsJSON: Data?,
        provenanceJSON: Data? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.parentID = parentID
        self.roleRaw = roleRaw
        self.kindRaw = kindRaw
        self.stateRaw = stateRaw
        self.text = text
        self.thinking = thinking
        self.branchIndex = branchIndex
        self.providerID = providerID
        self.modelID = modelID
        self.createdAt = createdAt
        self.draftsJSON = draftsJSON
        self.metricsJSON = metricsJSON
        self.provenanceJSON = provenanceJSON
    }
}
