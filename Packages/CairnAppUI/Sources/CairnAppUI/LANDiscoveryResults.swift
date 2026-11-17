import SwiftUI
import CairnChatDomain

/// The local-network section of the Servers screen: the button that starts a sweep, the progress of
/// one that is running, and the results as suggestions the user still has to add.
///
/// It renders nothing when no scanner is wired, so a build without the remote package — or a host
/// test — does not show a control that cannot work. CairnAppUI still imports no networking: the
/// scanner is injected as `ServerDiscovering`, and results are drafts, never saved profiles.
struct LANDiscoveryResults: View {
    var model: ServersModel
    /// Hands a finding to the editor as a draft. Saving happens there, on the user's tap.
    var onAdd: (DiscoveredServer) -> Void

    var body: some View {
        if model.discovering != nil {
            Section {
                controls
                ForEach(model.discovered) { server in
                    resultRow(server)
                }
                if model.scanHint != nil || !model.discovered.isEmpty {
                    Button("Clear results", role: .destructive) { model.clearDiscovery() }
                }
            } header: {
                Text("Local network")
            } footer: {
                Text(footer)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if model.isScanning {
            HStack {
                ProgressView(value: model.scanProgress?.fraction ?? 0)
                Text("\(model.scanProgress?.hostsDone ?? 0)/\(model.scanProgress?.hostsTotal ?? 0)")
                    .monospacedDigit()
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Button("Stop scan", role: .destructive) { model.stopLocalNetworkScan() }
        } else {
            Button {
                model.scanLocalNetwork()
            } label: {
                Label("Scan my network", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

    private func resultRow(_ server: DiscoveredServer) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.suggestedName)
                    .font(.callout)
                Text(detail(for: server))
                    .font(.caption.monospaced())
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Spacer()
            Button("Add") { onAdd(server) }
        }
        .accessibilityElement(children: .combine)
    }

    /// What a finding knows about the machine behind it: its address, how many models it showed,
    /// whether it asked for a key. Counts and an address only — never a response body.
    private func detail(for server: DiscoveredServer) -> String {
        var parts = [server.baseURLString]
        if let count = server.modelCount { parts.append("\(count) models") }
        if server.needsCredential { parts.append("wants a key") }
        return parts.joined(separator: " · ")
    }

    /// States what the scan is, what it is not, and what an empty result means. The hint from the
    /// domain — including the Local Network permission, whose denial fails every probe in a way
    /// that is indistinguishable from a closed port — replaces the default text when there is one.
    private var footer: String {
        if let hint = model.scanHint { return hint }
        if model.isScanning {
            return "Probing only the range this device is on. Nothing is saved, and you can stop."
        }
        return "Runs only when you tap it. A result is a suggestion you still have to add. The "
            + "first request to a new address is when iOS asks about the local network, and a "
            + "denial really does break the connection."
    }
}
