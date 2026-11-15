import Foundation
import SwiftData
import CairnChatDomain

/// Server profiles live in the same container as the chat: one container, one writer, one
/// context, so changing a server can never race a chat write.
///
/// The token is not here. `deleteProfile` removes the record only; the App layer pairs it
/// with `SecretStoring.removeSecret(for:)`, keeping Keychain policy out of the database.
extension SwiftDataStore: ServerProfileStoring {
    public func profiles() throws -> [ServerProfile] {
        let descriptor = FetchDescriptor<ServerProfileRecord>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map { $0.toProfile() }
    }

    public func save(_ profile: ServerProfile) throws {
        // Hoist captures: `#Predicate` is happiest with a plain local.
        let profileID = profile.id
        var descriptor = FetchDescriptor<ServerProfileRecord>(
            predicate: #Predicate { $0.id == profileID }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.name = profile.name
            existing.kindRaw = profile.kind.rawValue
            existing.baseURLString = profile.baseURLString
            existing.enabled = profile.enabled
            existing.publicInternetOptIn = profile.publicInternetOptIn
            existing.hasBearerToken = profile.hasBearerToken
            existing.headersJSON = profile.customHeaders.isEmpty ? nil : JSONCodec.encode(profile.customHeaders)
            existing.createdAt = profile.createdAt
            existing.updatedAt = profile.updatedAt
        } else {
            context.insert(ServerProfileRecord(profile))
        }
        try context.save()
    }

    public func delete(id: UUID) throws {
        var descriptor = FetchDescriptor<ServerProfileRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }
}
