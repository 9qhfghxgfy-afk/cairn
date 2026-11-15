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
                Button {
                    Task { await model.test(profile) }
                } label: {
                    if model.isBusy(profile) {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test")
                    }
                }
                Button("Models") {
                    Task { await model.refreshModels(profile) }
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
