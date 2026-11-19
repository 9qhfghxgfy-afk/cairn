import SwiftUI
import CairnChatDomain

/// The sentence saying search started going somewhere the user did not choose.
///
/// It appears when a row is deleted while active, or when the Ollama Cloud profile or its key goes away and
/// the cloud row goes with it. Both are recorded rather than just performed, and this is where the record is
/// read: results from DuckDuckGo look exactly like results from a self-hosted instance, so a reversion nobody
/// told the user about is a change of provider they cannot see.
///
/// It does not fade out. Dismissing it is the acknowledgement.
struct WebSearchRevertNoticeRow: View {
    let notice: String
    var onDismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice, systemImage: "arrow.uturn.backward.circle")
                .font(.callout)
                .foregroundStyle(CairnTheme.rust)
            Button("I understand", action: onDismiss)
                .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .contain)
    }
}

/// The Test Connection button and the line it answers with.
///
/// The answer is the same taxonomy the tool uses mid-conversation, so a row that tests `blocked` cannot
/// report "no results" in a chat. The latency is the measured round trip, not an estimate: the number is the
/// one a user on a tunnel would want, because it tells them whether the hop or the instance is the slow part.
struct WebSearchTestRow: View {
    let model: WebSearchSettingsModel
    let row: WebSearchProviderProfile
    let canTest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await model.runTest(for: row) }
            } label: {
                Text("Test \(row.displayName)")
            }
            .disabled(!canTest || model.isTestingID == row.id)

            if model.isTestingID == row.id {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(row.displayName) one harmless query…")
                }
            } else if let status = model.testStatuses[row.id] {
                Label(
                    status.detail(providerKind: row.kind),
                    systemImage: statusIsFailure(status)
                        ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(statusIsFailure(status) ? CairnTheme.rust : CairnTheme.amber)
            } else if canTest {
                Text("Not tested yet.")
            } else {
                Text("This build cannot open a connection to check a provider.")
            }
        }
        .font(.caption)
        .foregroundStyle(CairnTheme.stoneLight)
    }

    /// Empty is a working provider that found nothing for the test query, which is not a failure worth
    /// shouting about. Only a typed failure gets the warning colour.
    private func statusIsFailure(_ status: WebSearchTestStatus) -> Bool {
        if case .failure = status { return true }
        return false
    }
}
