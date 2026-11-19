import Foundation

/// The Ollama Cloud rows, reconciled from the server profiles that carry a search key.
///
/// This kind of provider is never added by hand and never removed by hand. It exists exactly as long as a
/// cloud profile with a key exists, because a search provider that cannot authenticate is worse than no
/// provider: it looks configured, and it fails. Reconciliation rather than events means a missed signal
/// cannot leave a dead row behind, and running the pass twice is invisible.
public extension WebSearchProviderStore {
    /// Adds, updates and drops the cloud rows to match the profiles that exist right now.
    ///
    /// The pass is deliberately quiet: a row that already says what it should say is left exactly as it is,
    /// so a re-sync on every settings write cannot move `updatedAt` under a user who edited nothing.
    mutating func sync(cloudMirrors: [WebSearchCloudMirror], now: Date = Date()) {
        let keyed = cloudMirrors.filter(\.hasKey)
        dropUnbackedCloudRows(keyed)
        for mirror in keyed { adoptCloudRow(for: mirror, now: now) }
    }

    /// Removes cloud rows no profile backs any more, reverting selection if one of them was active.
    private mutating func dropUnbackedCloudRows(_ keyed: [WebSearchCloudMirror]) {
        for row in providers where row.kind == .ollamaCloud {
            let stillBacked = row.sourceProfileID.map { source in
                keyed.contains { $0.sourceProfileID == source }
            } ?? false
            guard !stillBacked else { continue }
            providers.removeAll { $0.id == row.id }
            guard activeProviderID == row.id else { continue }
            revertToBuiltIn(reason: .cloudKeyRemoved, providerName: row.displayName)
        }
    }

    private mutating func adoptCloudRow(for mirror: WebSearchCloudMirror, now: Date) {
        let label = "Ollama Cloud — \(mirror.profileName)"
        guard let index = providers.firstIndex(where: {
            $0.kind == .ollamaCloud && $0.sourceProfileID == mirror.sourceProfileID
        }) else {
            providers.append(WebSearchProviderProfile(
                kind: .ollamaCloud,
                sourceProfileID: mirror.sourceProfileID,
                displayName: label,
                baseURLString: WebSearchProviderKind.ollamaCloudEndpoint,
                credentialShape: .bearer,
                hasCredential: true,
                createdAt: now,
                updatedAt: now
            ))
            return
        }
        guard providers[index].displayName != label || !providers[index].hasCredential else { return }
        providers[index].displayName = label
        providers[index].hasCredential = true
        providers[index].updatedAt = now
    }
}
