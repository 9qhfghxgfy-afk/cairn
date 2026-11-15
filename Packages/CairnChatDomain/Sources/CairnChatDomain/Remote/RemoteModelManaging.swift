import Foundation

/// Model-management boundary for a remote server. The UI derives every button from
/// `ProviderCapabilities`, so an OpenAI-compatible server never offers Pull / Delete /
/// loaded-model inspection that its API cannot serve.
@MainActor
public protocol RemoteModelManaging: AnyObject {
    func listModels(_ profile: ServerProfile) async throws -> [ModelInfo]
    func loadedModels(_ profile: ServerProfile) async throws -> [String]
    func pull(model: String, profile: ServerProfile) async throws
    func delete(model: String, profile: ServerProfile) async throws
}
