import SwiftUI
import CairnChatDomain

/// One server row: what it is, where its traffic goes, and only the actions its dialect can
/// actually serve. The badge is never hidden — the user should not have to guess whether
/// their prompt left the device.
///
/// `@MainActor` because the enable / opt-in bindings call straight into `ServersModel`.
@MainActor
struct ServerProfileRow: View {
    private var model: ServersModel
    private var profile: ServerProfile

    init(model: ServersModel, profile: ServerProfile) {
        self.model = model
        self.profile = profile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? "Untitled server" : profile.name)
                        .font(.headline)
                    Text(profile.baseURLString)
                        .font(.caption.monospaced())
                        .foregroundStyle(CairnTheme.stoneLight)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    NetworkBadge(networkClass: profile.networkClass)
                    if profile.isPlaintext {
                        PlaintextBadge()
                    }
                }
            }

            HStack(spacing: 10) {
                ServerStatusDot(status: model.status(for: profile))
                Text(profile.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                if profile.hasBearerToken {
                    Label("Token in Keychain", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.moss)
                }
                if let count = model.modelCounts[profile.id] {
                    Text("\(count) models")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                // Named per server: two machines with a model of the same name each remember their
                // own, and this line says which one this row will use next.
                if let lastModel = model.lastModel(for: profile) {
                    Text("last: \(lastModel)")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                        .lineLimit(1)
                }
            }

            // The key is in the Keychain, but the path is http — so it goes out in the clear on
            // every request. Shown on the row for the same reason the Plaintext badge is: the
            // user should not have to open the editor to learn how a prompt leaves the phone.
            if profile.credentialSentInClear {
                CredentialInClearWarning()
            }

            Toggle("Enabled", isOn: enabledBinding)
                .font(.callout)

            if profile.networkClass.requiresOptIn {
                Toggle("Allow requests to leave this device", isOn: optInBinding)
                    .font(.callout)
                    .tint(CairnTheme.rust)
                if !profile.publicInternetOptIn {
                    Text("Inert until you allow outbound requests.")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.rust)
                }
            }

            HStack(spacing: 8) {
                // One tap, and the next turn is answered here. Inert rows still show the button so
                // the reason is visible when it is pressed, rather than the row being silently
                // unselectable with no explanation.
                Button(model.isInUse(profile) ? "In use" : "Use") {
                    model.use(profile)
                }
                .disabled(model.isInUse(profile))
                Button {
                    Task { await model.test(profile) }
                } label: {
                    if model.isBusy(profile) {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test")
                    }
                }
                // Only kinds that declare a model list get the button, so the screen cannot offer
                // an endpoint this build has not declared.
                if profile.kind.backend.capabilities.modelListing {
                    Button("Models") {
                        Task { await model.refreshModels(profile) }
                    }
                }
                NavigationLink("Edit") {
                    ServerProfileEditor(model: model, profile: profile)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    model.delete(profile)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
            .disabled(model.isBusy(profile))

            if let outcome = model.outcomes[profile.id] {
                Label(outcome.userMessage, systemImage: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(outcome.isSuccess ? CairnTheme.moss : CairnTheme.rust)
            }
        }
        .padding(.vertical, 2)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { profile.enabled }, set: { model.setEnabled(profile, $0) })
    }

    private var optInBinding: Binding<Bool> {
        Binding(get: { profile.publicInternetOptIn }, set: { model.setOptIn(profile, $0) })
    }
}
