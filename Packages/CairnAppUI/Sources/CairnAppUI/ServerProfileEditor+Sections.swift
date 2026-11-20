import SwiftUI
import CairnChatDomain

extension ServerProfileEditor {
    @ViewBuilder var serverSection: some View {
        Section {
            InfoRow(key: .serverName) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
            }
            InfoRow(key: .serverBackend) {
                Picker("Type", selection: $kind) {
                    ForEach(ServerProfileKind.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .tint(CairnTheme.amber)
                .onChange(of: kind) { _, chosen in
                    applyKindChange(chosen)
                }
            }
            Text(kindEndpointsSummary)
                .font(.caption.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
            InfoRow(
                key: .serverAddress,
                caption: "http is accepted for a machine on your own network; https for anything public."
            ) {
                TextField("Base URL", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())
            }
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
            if kind == .ollamaCloud && draft.networkClass == .publicInternet && !optIn {
                Text("Inert until you allow requests to leave this device.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
            }
        } header: {
            Text("Server")
        } footer: {
            Text(kindFooter)
        }
    }

    @ViewBuilder var trafficSection: some View {
        Section {
            InfoRow(key: .serverUseEnabled) {
                Toggle("Use this server", isOn: $enabled)
                    .tint(CairnTheme.amber)
            }
            if draft.networkClass.requiresOptIn {
                InfoRow(key: .serverPublicOptIn) {
                    Toggle("Allow requests to leave this device", isOn: $optIn)
                        .tint(CairnTheme.rust)
                }
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
            InfoSectionHeader("Token", key: .serverToken)
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
            InfoSectionHeader("Custom headers", key: .serverCustomHeaders)
        } footer: {
            Text(headerFooter)
        }
    }
}
