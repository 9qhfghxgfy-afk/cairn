import Foundation
import Observation
import CairnChatDomain

/// View model behind the Servers screen.
///
/// It talks only to domain protocols, so CairnAppUI still imports neither SwiftData nor
/// URLSession: the App layer injects the profile store, the tester, the model service, the
/// Keychain-backed secret store, and a closure that turns saved profiles into engines.
/// That seam is what keeps these screens compiling in a CI job that has no socket at all.
@Observable @MainActor
public final class ServersModel {
    public private(set) var profiles: [ServerProfile] = []
    public private(set) var outcomes: [UUID: RemoteTestOutcome] = [:]
    public private(set) var modelCounts: [UUID: Int] = [:]
    public private(set) var busyIDs: Set<UUID> = []
    public var notice: String?

    private let storing: any ServerProfileStoring
    private let testing: any RemoteTesting
    private let managing: any RemoteModelManaging
    private let secrets: any SecretStoring
    private let registry: ProviderRegistry?
    private let baseEngines: [any InferenceProvider]
    /// Not `@Sendable` on purpose: this is only ever called from the main actor, and keeping
    /// it main-actor-bound lets the App pass a factory that owns the URLSession transport.
    private let engineBuilder: ([ServerProfile]) -> [any InferenceProvider]

    public init(
        storing: any ServerProfileStoring,
        testing: any RemoteTesting,
        managing: any RemoteModelManaging,
        secrets: any SecretStoring,
        registry: ProviderRegistry? = nil,
        baseEngines: [any InferenceProvider] = [],
        engineBuilder: @escaping ([ServerProfile]) -> [any InferenceProvider] = { _ in [] }
    ) {
        self.storing = storing
        self.testing = testing
        self.managing = managing
        self.secrets = secrets
        self.registry = registry
        self.baseEngines = baseEngines
        self.engineBuilder = engineBuilder
        reload()
    }

    public func reload() {
        do {
            profiles = try storing.profiles()
            publishEngines()
        } catch {
            notice = "Could not read saved servers: \(error.localizedDescription)"
        }
    }

    /// Validates and canonicalizes through the domain rules, then stores. A profile never
    /// reaches disk with a path, a query fragment, or a credential in its URL.
    ///
    /// `token`: nil leaves the stored token untouched, `""` removes it, anything else
    /// replaces it. The token only ever goes to the Keychain, and the profile record keeps
    /// the display flag `hasBearerToken` so the list can say "token stored" without
    /// unlocking anything.
    @discardableResult
    public func save(_ profile: ServerProfile, token: String?) -> Bool {
        var stored = profile
        stored.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try ServerProfile.validate(
                name: stored.name,
                urlString: profile.baseURLString,
                headers: profile.customHeaders
            )
            guard let canonical = ServerProfile.canonicalize(urlString: profile.baseURLString) else {
                notice = ServerProfileValidationError.invalidURL.errorDescription
                return false
            }
            stored.baseURLString = canonical
            stored.updatedAt = Date()
            if let token {
                try secrets.setSecret(token, for: stored.id)
                stored.hasBearerToken = !token.isEmpty
            }
            try storing.save(stored)
            reload()
            return true
        } catch let issue as ServerProfileValidationError {
            notice = issue.errorDescription
            return false
        } catch {
            notice = "Could not save \(stored.name): \(error.localizedDescription)"
            return false
        }
    }

    public func delete(_ profile: ServerProfile) {
        do {
            try storing.delete(id: profile.id)
            // The record is gone, so the Keychain item has to go with it: an orphaned token
            // is a credential with nothing to point at.
            try secrets.removeSecret(for: profile.id)
            outcomes[profile.id] = nil
            modelCounts[profile.id] = nil
            reload()
        } catch {
            notice = "Could not delete \(profile.name): \(error.localizedDescription)"
        }
    }

    public func setEnabled(_ profile: ServerProfile, _ enabled: Bool) {
        var updated = profile
        updated.enabled = enabled
        save(updated, token: nil)
    }

    public func setOptIn(_ profile: ServerProfile, _ optIn: Bool) {
        var updated = profile
        updated.publicInternetOptIn = optIn
        save(updated, token: nil)
    }

    public func removeToken(_ profile: ServerProfile) {
        save(profile, token: "")
    }

    public func hasToken(_ profile: ServerProfile) -> Bool {
        secrets.secret(for: profile.id) != nil
    }

    public func test(_ profile: ServerProfile) async {
        busyIDs.insert(profile.id)
        outcomes[profile.id] = nil
        outcomes[profile.id] = await testing.test(profile)
        busyIDs.remove(profile.id)
    }

    public func refreshModels(_ profile: ServerProfile) async {
        busyIDs.insert(profile.id)
        do {
            modelCounts[profile.id] = try await managing.listModels(profile).count
        } catch {
            modelCounts[profile.id] = nil
            notice = error.localizedDescription
        }
        busyIDs.remove(profile.id)
    }

    public func isBusy(_ profile: ServerProfile) -> Bool {
        busyIDs.contains(profile.id)
    }

    /// Engines follow the profile list: disabled profiles and un-opted-in public servers
    /// are excluded by the builder, so a profile the user turned off cannot answer a turn.
    private func publishEngines() {
        guard let registry else { return }
        registry.update(baseEngines + engineBuilder(profiles))
    }
}
