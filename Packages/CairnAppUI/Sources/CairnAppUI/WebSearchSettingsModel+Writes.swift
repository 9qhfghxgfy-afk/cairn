import Foundation
import CairnChatDomain

/// The write path: add, edit, delete, credential, and Test Connection.
///
/// The order of operations in `save` is the part worth reading. A row is validated and stored **before** its
/// token is written, because the other order leaves an orphaned credential in the Keychain attached to a row
/// that was refused. And a token is never read back out of the Keychain to be displayed — the screen shows
/// whether one exists, which is the only fact a settings list needs.
public extension WebSearchSettingsModel {
    /// Adds a new row, or edits an existing one. Returns false and leaves everything untouched when the
    /// domain refuses the row, with the domain's own sentence in `lastError`.
    @discardableResult
    func save(_ edit: WebSearchRowEdit) -> Bool {
        var search = theme.settings.webSearch
        let headers = Self.cleanHeaders(edit.customHeaders)
        let endpointChanged = edit.id.flatMap { search.providers.profile(id: $0)?.baseURLString }
            .map { $0 != edit.address.trimmingCharacters(in: .whitespacesAndNewlines) } ?? true
        var row = WebSearchProviderProfile(
            id: edit.id ?? UUID(),
            kind: .searxng,
            displayName: edit.name,
            baseURLString: edit.address,
            categories: edit.categories,
            language: edit.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : edit.language,
            safeSearch: edit.safeSearch,
            timeRange: edit.timeRange,
            timeoutSeconds: edit.timeoutSeconds,
            credentialShape: edit.credentialShape,
            hasCredential: hasSecretAfter(edit),
            customHeaders: headers
        )
        do {
            if let id = edit.id {
                try search.providers.update(id: id) { stored in stored = row }
            } else {
                try search.providers.add(row)
            }
        } catch let issue as WebSearchProviderValidationError {
            lastError = issue.errorDescription
            return false
        } catch {
            lastError = "That provider could not be saved."
            return false
        }

        // Only now does the secret have something to belong to.
        if let token = edit.token, let secrets = searchSecrets {
            do { try secrets.setSecret(token, for: row.id) }
            catch {
                lastError = "The address was saved, but the credential could not be stored."
                return false
            }
            row.hasCredential = secrets.secret(for: row.id) != nil
            try? search.providers.update(id: row.id) { stored in
                stored.hasCredential = row.hasCredential
            }
        }
        // An address edit points the same row at a different machine, and a permission given to the old one
        // does not travel with it. The next search asks again.
        if endpointChanged { search.consent.revoke(providerID: row.id, kind: row.kind) }
        theme.setWebSearch(search)
        lastError = nil
        return true
    }

    /// Deletes a row. The built-in row refuses, and deleting the active row is what produces the revert
    /// notice rather than a silent change of provider.
    ///
    /// The row's grant and its secret go with it: a grant left behind is a permission for a machine that no
    /// longer exists, and an orphaned token is a credential with nothing to point at.
    @discardableResult
    func remove(_ row: WebSearchProviderProfile) -> Bool {
        var search = theme.settings.webSearch
        do {
            guard try search.providers.remove(id: row.id) != nil else { return false }
        } catch let issue as WebSearchProviderValidationError {
            lastError = issue.errorDescription
            return false
        } catch {
            lastError = "That provider could not be deleted."
            return false
        }
        search.consent.revoke(providerID: row.id, kind: row.kind)
        search.consent.removingProviders(notIn: search.providers)
        try? searchSecrets?.removeSecret(for: row.id)
        testStatuses[row.id] = nil
        theme.setWebSearch(search)
        lastError = nil
        return true
    }

    /// Runs one fixed query against one row, and stores the answer under that row.
    func runTest(for row: WebSearchProviderProfile) async {
        guard let testing else {
            lastError = "This build cannot test a connection."
            return
        }
        isTestingID = row.id
        testStatuses[row.id] = nil
        // Whatever vault owns this row's secret, and no other. A cloud row is tested with its own profile's
        // key; a built-in row with nothing at all.
        testStatuses[row.id] = await testing.run(
            profile: row, credential: credential(for: row), resultCount: resultCount
        )
        isTestingID = nil
    }

    /// Whether a token is stored for the row right now — read from the vault, never from a displayed value.
    func secretIsStored(for row: WebSearchProviderProfile) -> Bool {
        credential(for: row) != nil
    }

    /// Three states, so an edit of a row's name cannot be read as a request to delete its credential.
    private func hasSecretAfter(_ edit: WebSearchRowEdit) -> Bool {
        if let token = edit.token {
            return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let id = edit.id else { return false }
        return searchSecrets?.secret(for: id) != nil
    }

    /// Header rows with empty names dropped and blank values trimmed. Names that can only carry a credential
    /// are refused by validation rather than stripped here — silently dropping a row the user can see on
    /// screen is a store that disagrees with the editor.
    private static func cleanHeaders(_ headers: [String: String]) -> [String: String] {
        var cleaned: [String: String] = [:]
        for (name, value) in headers {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            cleaned[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}

