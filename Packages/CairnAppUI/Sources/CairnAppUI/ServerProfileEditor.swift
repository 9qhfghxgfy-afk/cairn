import SwiftUI
import CairnChatDomain

/// Editor for one server profile.
///
/// The URL field is live-validated with the same domain rules the save path uses, the token
/// field writes only to the Keychain, and a credential-bearing header name is refused with
/// an explanation instead of being silently dropped. The section bodies live in
/// `ServerProfileEditor+Sections.swift`; members are module-internal so that file can bind
/// to them.
///
/// `@MainActor` because every action here goes through `ServersModel`, which is main-actor
/// isolated, and the save path touches the Keychain.
@MainActor
struct ServerProfileEditor: View {
    struct HeaderRow: Identifiable {
        let id = UUID()
        var name: String
        var value: String
    }

    /// Header names that carry a credential. Validation refuses `Authorization` outright;
    /// the others are warned about here because their values would land in the settings db.
    static let credentialLikeHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "x-api-key", "api-key",
    ]

    var model: ServersModel
    var profile: ServerProfile
    @Environment(\.dismiss) private var dismiss

    // @State, not plain vars: the editor owns these while the sheet is open, and the
    // section file binds to them with $name, $urlString, and so on.
    @State var name: String
    @State var kind: ServerProfileKind
    @State var urlString: String
    @State var headerRows: [HeaderRow]
    @State var enabled: Bool
    @State var optIn: Bool
    /// Written to the Keychain on save: never to the settings store, never kept in memory
    /// once the sheet closes.
    @State var token = String()

    init(model: ServersModel, profile: ServerProfile) {
        self.model = model
        self.profile = profile
        _name = State(initialValue: profile.name)
        _kind = State(initialValue: profile.kind)
        _urlString = State(initialValue: profile.baseURLString)
        _headerRows = State(initialValue: profile.customHeaders
            .sorted { $0.key < $1.key }
            .map { HeaderRow(name: $0.key, value: $0.value) })
        _enabled = State(initialValue: profile.enabled)
        _optIn = State(initialValue: profile.publicInternetOptIn)
    }

    var body: some View {
        Form {
            serverSection
            trafficSection
            tokenSection
            headersSection
            Section {
                Button("Save") { save() }
            }
        }
        .navigationTitle(profile.name.isEmpty ? "New server" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var headers: [String: String] {
        var stored: [String: String] = [:]
        for row in headerRows {
            let key = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            stored[key] = row.value
        }
        return stored
    }

    var draft: ServerProfile {
        ServerProfile(
            id: profile.id,
            name: name,
            kind: kind,
            baseURLString: urlString,
            customHeaders: headers,
            hasBearerToken: profile.hasBearerToken,
            enabled: enabled,
            publicInternetOptIn: optIn,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    var validationIssue: String? {
        guard !trimmedURL.isEmpty else { return "Enter the server URL." }
        do {
            try ServerProfile.validate(name: name, urlString: trimmedURL, headers: headers)
            return nil
        } catch let issue as ServerProfileValidationError {
            return issue.errorDescription
        } catch {
            return "The URL could not be checked."
        }
    }

    /// Honest traffic summary for the editor footer. The rule it states is the app's
    /// real one: plaintext is allowed only where the path is the user's own network —
    /// a LAN segment, or a VPN tunnel that carries its own encryption — and a
    /// public-internet address always needs https plus the outbound opt-in.
    var trafficFooter: String {
        if draft.networkClass.allowsPlaintext {
            if draft.isPlaintext {
                return "Private address over http: your prompts cross your own network "
                    + "unencrypted. Inside a WireGuard tunnel that path is already "
                    + "encrypted; across plain Wi-Fi it is not."
            }
            return "Private address over https, so the connection is encrypted end to end."
        }
        return "This address is on the public internet, so it needs https:// and the "
            + "outbound opt-in."
    }

    var headerFooter: String {
        let names = headers.keys.map { $0.lowercased() }
        if let hit = names.first(where: { Self.credentialLikeHeaders.contains($0) }) {
            return "\"\(hit)\" carries a credential, so it is refused: put the value in the token field, which is Keychain-backed."
        }
        return "Sent with every request to this server. Values live in the settings database, so keep secrets out of them."
    }

    func save() {
        // A nil token means "leave the Keychain alone"; the field is never read back out.
        if model.save(draft, token: token.isEmpty ? nil : token) { dismiss() }
    }
}
