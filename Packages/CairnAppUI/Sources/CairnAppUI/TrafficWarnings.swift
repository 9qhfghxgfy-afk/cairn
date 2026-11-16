import SwiftUI
import CairnChatDomain

/// Shown when a profile has a bearer token and its traffic reaches the server unencrypted, so
/// the token crosses the network in the clear on every request.
///
/// Plaintext on a private network is allowed by design — it is the whole point of the LAN and
/// WireGuard routes — so the response here is visibility rather than refusal. A key in front of
/// a home server is a reasonable thing to want; it just should not be invisible. The rule lives
/// in the domain (`ServerProfile.credentialSentInClear`) so it is unit-tested, and both the
/// server row and the editor display this one view.
public struct CredentialInClearWarning: View {
    public init() {}

    public var body: some View {
        Label("Token crosses the network unencrypted", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(CairnTheme.rust)
            .accessibilityLabel("A bearer token is sent to this server without encryption")
    }
}
