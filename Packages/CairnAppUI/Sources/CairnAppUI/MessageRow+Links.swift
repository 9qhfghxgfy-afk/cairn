import SwiftUI
import CairnChatDomain

/// A link inside an answer, and the decision about leaving for it.
///
/// A model's answer can contain a link the user never asked for. Following it means leaving the app for the
/// network, which is the one thing this app only ever does with the person in the loop — so the tap is
/// caught, the host is named, and only an explicit "Open" leaves. The row holds the URL rather than opening
/// it, which is what lets the tap that asked be the tap that gets asked back.
extension MessageRow {

    func openExternal(_ url: URL) { externalURL = url }

    /// The site, or the plainest possible description of it. A host is not a secret and is not logged; it is
    /// shown to the person about to leave for it, which is the only place it belongs.
    func externalTitle(for url: URL?) -> String {
        guard let host = url?.host, !host.isEmpty else { return "Open this link?" }
        return "Open \(host) in Safari?"
    }

    var isOpeningExternal: Binding<Bool> {
        Binding(get: { externalURL != nil }, set: { if !$0 { externalURL = nil } })
    }

    @ViewBuilder var externalButtons: some View {
        Button("Cancel", role: .cancel) { externalURL = nil }
        Button("Open") {
            // The URL was kept rather than followed a moment ago; this is the only route out, and it opens
            // what the user was shown the host of, not what the link text claimed.
            if let url = externalURL { openExternalURL(url) }
            externalURL = nil
        }
    }
}
