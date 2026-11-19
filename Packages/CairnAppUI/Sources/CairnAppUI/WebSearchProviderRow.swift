import SwiftUI
import CairnChatDomain

extension WebSearchProviderProfile {
    /// Where a row's traffic goes, in the same three honest words the server list uses. The row has to say
    /// this without being opened, because "which provider is active" is a question about where the user's
    /// words end up.
    var networkLabel: String {
        switch networkClass {
        case .publicInternet: return "Public internet — your query leaves this device."
        case .privateLan: return "Your own network."
        case .privateVPN: return "Your own network, through your tunnel."
        case .onDevice: return "This device."
        }
    }

    /// The line under a row's name: the address for a row the user typed, the fixed truth for a row Cairn
    /// addresses. An IP-literal host is shown as the address it is, since the row's address field is where
    /// it came from.
    var subLabel: String {
        let endpoint = host.isEmpty ? baseURLString : host
        if !parameterSummary.isEmpty { return "\(endpoint) · \(parameterSummary)" }
        return endpoint
    }
}

/// One provider row: what it is, where it goes, whether it is the one in use, and what may be done to it.
///
/// Only a hand-added SearXNG row is editable or deletable. The built-in row cannot be removed — there has to
/// be a provider left when a self-hosted instance stops answering — and a cloud row is not a thing a person
/// adds, so it is not a thing they delete either. It follows the profile and its key.
struct WebSearchProviderRow: View {
    let model: WebSearchSettingsModel
    let row: WebSearchProviderProfile
    var onEdit: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(row.displayName).font(.subheadline)
                if row.id == model.active.id {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CairnTheme.amber)
                }
                Spacer(minLength: 0)
                if row.isBuiltIn {
                    Text("Built in").font(.caption2).foregroundStyle(CairnTheme.stoneLight)
                } else if row.sourceProfileID != nil {
                    Text("Automatic").font(.caption2).foregroundStyle(CairnTheme.stoneLight)
                } else {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit \(row.displayName)")
                }
            }
            Text(row.subLabel)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            if let note = WebSearchAttribution.note(for: row.kind) {
                Text(note).font(.caption2).foregroundStyle(CairnTheme.stoneLight)
            }
            HStack(spacing: 8) {
                if row.usesPlaintext {
                    Text("Plaintext")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CairnTheme.rust)
                }
                if row.credentialShape != nil {
                    Text(
                        model.secretIsStored(for: row)
                            ? "Credential stored"
                            : "No credential yet"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        model.secretIsStored(for: row)
                            ? CairnTheme.stoneLight : CairnTheme.rust
                    )
                }
                Text(stateLine).font(.caption2).foregroundStyle(CairnTheme.stoneLight)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if isHandOwned {
                Button("Delete", role: .destructive) {
                    model.remove(row)
                }
                .accessibilityLabel("Delete \(row.displayName)")
            }
        }
    }

    /// Only a row a person added is theirs to delete. The built-in row is the way back, and a cloud row
    /// belongs to the profile that materialised it.
    private var isHandOwned: Bool { !row.isBuiltIn && row.sourceProfileID == nil }

    /// The consent record, stated. A row on the user's own network is never asked about, and saying so here
    /// is what keeps "Allowed" from reading as though a warning had been waved through.
    private var stateLine: String {
        switch model.consent(for: row) {
        case .granted:
            return row.reachesPublicInternet ? "Allowed" : "Local — never asked"
        case .denied: return "You said no"
        case .undecided: return "Will ask first"
        }
    }
}
