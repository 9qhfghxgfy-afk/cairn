import Foundation
@testable import CairnChatDomain

/// The doubles behind the server-switch tests. A saved server is only ever a `ServerProfile` plus
/// an engine built from it, so the double is a profile with a fixed catalog and the engine id that
/// profile really gets (`RemoteEngineID`) — which is exactly what a switch has to line up with.
/// `stream` finishes immediately: these tests are about which engine a turn would go to, not about
/// generation, and a mock that streamed would only make the switch slower to assert.
struct ServerEngineStub: InferenceProvider {
    let profile: ServerProfile
    let modelIDs: [String]

    var id: String { profile.engineID }
    var displayName: String { profile.name }
    var networkClass: NetworkClass { profile.networkClass }
    var capabilities: ProviderCapabilities { profile.kind.backend.capabilities }
    var serverProfileID: UUID? { profile.id }

    func models() async throws -> [ModelInfo] {
        modelIDs.map { ModelInfo(id: $0, displayName: $0, providerID: id) }
    }

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// The selection store as the tests see it: the same value a SwiftData row holds, kept in memory,
/// with the number of writes recorded so a write-through can be told apart from an in-memory-only
/// change.
@MainActor
final class RecordingSelectionStore: ServerSelectionStoring {
    var stored = ServerSelection()
    var saveCount = 0
    var failure: Error?

    func selection() throws -> ServerSelection {
        if let failure { throw failure }
        return stored
    }

    func saveSelection(_ selection: ServerSelection) throws {
        if let failure { throw failure }
        stored = selection
        saveCount += 1
    }
}
