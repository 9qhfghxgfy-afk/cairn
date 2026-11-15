import Foundation
import CairnChatDomain

/// Test doubles for the Servers screen. Every one of them sits behind a domain protocol, so
/// `CairnAppUI` never needs a store, a Keychain, or a socket to be tested.
@MainActor
final class RecordingProfileStore: ServerProfileStoring {
    var saved: [UUID: ServerProfile] = [:]
    var deleted: [UUID] = []
    var failure: Error?

    func profiles() throws -> [ServerProfile] {
        if let failure { throw failure }
        return saved.values.sorted { $0.name < $1.name }
    }

    func save(_ profile: ServerProfile) throws {
        if let failure { throw failure }
        saved[profile.id] = profile
    }

    func delete(id: UUID) throws {
        saved.removeValue(forKey: id)
        deleted.append(id)
    }
}

@MainActor
final class MemorySecretStore: SecretStoring {
    var items: [UUID: String] = [:]

    func setSecret(_ secret: String, for id: UUID) throws {
        // Same policy as the Keychain store: an empty value is a delete, not an empty secret.
        if secret.isEmpty {
            items[id] = nil
        } else {
            items[id] = secret
        }
    }

    func secret(for id: UUID) -> String? {
        items[id]
    }

    func removeSecret(for id: UUID) throws {
        items[id] = nil
    }
}

@MainActor
final class StubTester: RemoteTesting {
    var outcome: RemoteTestOutcome = .connected(version: nil, modelCount: 0, latencyMilliseconds: 1)
    var tested: [UUID] = []

    func test(_ profile: ServerProfile) async -> RemoteTestOutcome {
        tested.append(profile.id)
        return outcome
    }
}

@MainActor
final class StubModelService: RemoteModelManaging {
    var models: [ModelInfo] = [ModelInfo(id: "qwen3:8b", displayName: "qwen3:8b", providerID: "remote")]
    var failure: Error?

    func listModels(_ profile: ServerProfile) async throws -> [ModelInfo] {
        if let failure { throw failure }
        return models
    }

    func loadedModels(_ profile: ServerProfile) async throws -> [String] { [] }

    func pull(model: String, profile: ServerProfile) async throws {}

    func delete(model: String, profile: ServerProfile) async throws {}
}
