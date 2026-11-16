import SwiftUI
import CairnChatDomain

/// The editor's honest account of where the traffic goes and what it carries. Kept apart from
/// the view body so each file stays small and one-purpose: this half is prose and the two rules
/// the prose depends on, and both are derived from the same domain checks the save path uses
/// (`NetworkClass.allowsPlaintext`, `ServerProfile.isPlaintext`,
/// `ServerProfile.credentialSentInClear`) rather than from a second copy of the policy.
extension ServerProfileEditor {
    /// Private addresses may be plaintext: the path is either the user's own network or a VPN
    /// tunnel that carries its own encryption. A public-internet address always needs https plus
    /// the outbound opt-in, and validation refuses anything else, so this text can describe the
    /// two real cases without hedging.
    var trafficFooter: String {
        if draft.networkClass.allowsPlaintext {
            if draft.isPlaintext {
                return "Private address over http: your prompts cross your own network "
                    + "unencrypted. Inside a WireGuard tunnel that path is already "
                    + "encrypted; across plain Wi-Fi it is not."
            }
            return "Private address over https, so the connection is encrypted end to end."
        }
        return "This address is on the public internet, so it needs https:// and the "
            + "outbound opt-in."
    }

    /// Whether saving right now would send a bearer token over an unencrypted path. This is the
    /// editor's view of `ServerProfile.credentialSentInClear`, and it has to account for two
    /// things a saved profile cannot know: a token being typed into this sheet, and a stored
    /// token the user has just removed here.
    var credentialSentInClear: Bool {
        guard draft.isPlaintext else { return false }
        let typed = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return typed || (profile.hasBearerToken && !tokenClearedHere)
    }
}
