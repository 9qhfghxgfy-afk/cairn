import SwiftUI
import CairnChatDomain

extension ServerProfileEditor {
    @ViewBuilder var serverSection: some View {
        Section("Server") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.never)
            Picker("Type", selection: $kind) {
                ForEach(ServerProfileKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            TextField("Base URL", text: $urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.body.monospaced())
            if let issue = validationIssue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
            } else if let canonical = ServerProfile.canonicalize(urlString: trimmedURL) {
                Text("Saved as \(canonical)")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            NetworkBadge(networkClass: draft.networkClass)
            if draft.isPlaintext {
                PlaintextBadge()
            }
        }
    }

    @ViewBuilder var trafficSection: some View {
        Section {
            Toggle("Use this server", isOn: $enabled)
            if draft.networkClass.requiresOptIn {
                Toggle("Allow requests to leave this device", isOn: $optIn)
                    .tint(CairnTheme.rust)
            }
        } header: {
            Text("Traffic")
        } footer: {
            Text(trafficFooter)
        }
    }

    @ViewBuilder var tokenSection: some View {
        Section {
            SecureField(
                profile.hasBearerToken ? "Stored — type to replace" : "Bearer token",
                text: $token
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if profile.hasBearerToken {
                Button("Remove stored token") {
                    token = ""
                    tokenClearedHere = true
                    model.removeToken(profile)
                }
                .font(.caption)
            }
            // A token and an http URL: the key will cross the network in the clear. Allowed on
            // a private network, but never shown silently.
            if credentialSentInClear {
                CredentialInClearWarning()
            }
        } header: {
            Text("Token")
        } footer: {
            Text("Saved in the Keychain on this device only. Never written to the settings database, never logged.")
        }
    }

    @ViewBuilder var headersSection: some View {
        Section {
            ForEach($headerRows) { $row in
                HStack {
                    TextField("Header", text: $row.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Value", text: $row.value)
                }
            }
            .onDelete { offsets in
                headerRows.remove(atOffsets: offsets)
            }
            Button("Add header") {
                headerRows.append(HeaderRow(name: "", value: ""))
            }
            .font(.caption)
        } header: {
            Text("Custom headers")
        } footer: {
            Text(headerFooter)
        }
    }
}
