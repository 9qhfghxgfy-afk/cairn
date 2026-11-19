import SwiftUI
import CairnChatDomain

/// The credential and header sections of the provider editor.
///
/// Split out only to keep each file about one thing; the rules in here are the ones worth reading. A token is
/// written to the Keychain by `WebSearchSettingsModel.save` after the row validates, and nowhere else.
/// Nothing on this screen can show a stored token, because a screen that can show one is a screen that can be
/// screenshotted, and a search instance's token is the key to whoever else can use that instance.
extension WebSearchProviderEditor {

    var credentialSection: some View {
        Section {
            Picker(selection: $choice, label: Text("Credential")) {
                ForEach(CredentialChoice.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.navigationLink)

            if choice == .namedHeader {
                TextField("Header name", text: $secretHeaderName, prompt: Text("X-API-Key"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if choice != .none {
                SecureField(
                    storedCredentialPresent
                        ? "Stored — type a new one to replace it" : "Token",
                    text: $token
                )
                if storedCredentialPresent {
                    Toggle(isOn: $removingStored) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Remove the stored credential").font(.subheadline)
                            Text("The address stays; the Keychain entry goes.")
                                .font(.caption)
                                .foregroundStyle(CairnTheme.stoneLight)
                        }
                    }
                    .tint(CairnTheme.rust)
                }
            }
        } header: {
            Text("Credential")
        } footer: {
            Text(
                "The value goes to the Keychain and nowhere else — not into the settings store, not back onto "
                    + "this screen. Names that can only carry a credential (Authorization, X-API-Key, "
                    + "Api-Key, Proxy-Authorization, Cookie) are refused in the ordinary header rows below: a "
                    + "header row is a settings value, and a secret in a settings value is a secret in the clear."
            )
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        }
    }

    /// Whether a secret is already stored for the row being edited. Presence only — the value is never read
    /// out to be shown.
    var storedCredentialPresent: Bool {
        guard let id = draft.id,
              let row = model.search.providers.profile(id: id) else { return false }
        return model.secretIsStored(for: row)
    }

    var headerSection: some View {
        Section {
            ForEach($headerRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Header name", text: row.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Value", text: row.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        headerRows.removeAll { $0.id == row.id }
                    }
                }
            }
            Button {
                headerRows.append(HeaderRow(name: "", value: ""))
            } label: {
                Label("Add header", systemImage: "plus")
            }
        } header: {
            Text("Extra headers")
        } footer: {
            Text(
                "For an instance that needs something ordinary sent with every request — a proxy's routing "
                    + "header, say. These values are stored on the device in plain settings and go with each "
                    + "search. Put nothing here that is a secret."
            )
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        }
    }

    /// The three states of the token field, resolved. Untouched is nil ("keep what is stored"), the remove
    /// switch is the empty string ("delete it"), and anything typed replaces it.
    var tokenState: String? {
        if !token.isEmpty { return token }
        if removingStored { return "" }
        return nil
    }

    /// A row is only saved when the domain accepts it. A refusal leaves the sheet open with the reason
    /// showing, because a row that does not validate is a row that cannot answer a search later.
    func save() {
        var edit = draft
        edit.name = name
        edit.address = address
        edit.categories = splitCategories(categories)
        edit.language = language
        edit.timeoutSeconds = timeoutSeconds
        edit.credentialShape = shape(for: choice, headerName: secretHeaderName)
        edit.token = tokenState
        edit.customHeaders = headerRows.reduce(into: [:]) { found, row in
            let key = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { found[key] = row.value }
        }
        if model.save(edit) { dismiss() }
    }

    static func choice(for shape: WebSearchCredentialShape?) -> CredentialChoice {
        switch shape {
        case nil: return .none
        case .bearer: return .bearer
        case .secretHeader: return .namedHeader
        }
    }

    func shape(for option: CredentialChoice, headerName: String) -> WebSearchCredentialShape? {
        switch option {
        case .none: return nil
        case .bearer: return .bearer
        case .namedHeader:
            return .secretHeader(name: headerName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func splitCategories(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

}
