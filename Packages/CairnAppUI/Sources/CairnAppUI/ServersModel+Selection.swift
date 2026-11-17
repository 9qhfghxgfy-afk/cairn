import Foundation
import CairnChatDomain

/// The parts of the Servers screen that are about *choosing* a server rather than configuring one.
///
/// Kept apart from the profile CRUD so the rule "one tap changes what the next turn uses" lives in
/// one place, next to the status derivation that decides whether a row may even offer that tap.
extension ServersModel {
    /// The row's dot. Derived every read from what the profile is allowed to do plus what the last
    /// test said — never from a remembered success, because a box that slept an hour ago is not
    /// "connected".
    public func status(for profile: ServerProfile) -> ServerConnectionStatus {
        ServerConnectionStatus.derive(
            profile: profile,
            outcome: outcomes[profile.id],
            isTesting: isBusy(profile)
        )
    }

    /// The server a chat should be pointed at, or nil when nothing can answer. Falls back to the
    /// first usable server when the stored choice is deleted, switched off, or un-opted-in, so the
    /// app is never silently pointing at nothing.
    public func activeProfile() -> ServerProfile? {
        selection?.selection.resolvedActive(in: profiles)
    }

    public func isInUse(_ profile: ServerProfile) -> Bool {
        activeProfile()?.id == profile.id
    }

    /// One tap: this server answers the next turn, and a chat restores the model it was last used
    /// with on that server. A server that cannot answer — switched off, or a public server with no
    /// outbound opt-in — is refused out loud instead of being made active anyway.
    public func use(_ profile: ServerProfile) {
        guard profile.usableNow else {
            notice = if profile.networkClass.requiresOptIn && !profile.publicInternetOptIn {
                "Turn on \"\(profile.name)\" and allow requests to leave this device before using it."
            } else {
                "Turn on \"\(profile.name)\" before using it."
            }
            return
        }
        selection?.setActive(profile.id)
        onActiveServerChange?(profile)
    }

    /// A new profile as that kind wants to start — the cloud kind arrives named, prefilled, and
    /// switched off; a LAN kind arrives empty, because nobody should guess the user's address.
    public func draft(for kind: ServerProfileKind) -> ServerProfile {
        ServerProfile.draft(for: kind)
    }

    /// The remembered model for a server, so the row can name what it will use next.
    public func lastModel(for profile: ServerProfile) -> String? {
        selection?.lastModel(forProfile: profile.id)
    }

    /// Points the shared choice at something real. Called after every reload: a profile deleted
    /// elsewhere, switched off, or expired out of the opt-in must not stay "active".
    func reconcileSelection() {
        guard let selection else { return }
        selection.reload()
        let resolved = selection.selection.resolvedActive(in: profiles)
        if selection.selection.activeProfileID != resolved?.id {
            selection.setActive(resolved?.id)
        }
    }
}
