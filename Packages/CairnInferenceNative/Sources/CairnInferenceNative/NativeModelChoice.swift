import Foundation

/// Which folder one turn loads, out of the ones this phone holds.
///
/// Pure, and separate from the actor, because this is the rule that decides whether a person's choice is
/// honoured — and a rule that only runs inside an actor in front of a C++ runtime can only be tested on a
/// phone.
///
/// * No preference — nothing asked, a blank name, or the legacy engine-wide id this provider used before
///   folders had names of their own: keep what is already resident, and if that folder is gone, take the
///   newest one that exists. Loading a different folder means evicting the one that is answering, so an
///   unasked-for swap must not happen silently, and a phone whose chosen model was deleted still answers.
/// * A named model that is installed: that folder, whatever was live before.
/// * A named model that is **not** installed: no folder, which the provider reports as
///   `NativeGenerationError.modelNotInstalled`. Falling back here would be the worse failure — the person
///   picked one model and got another, with nothing on screen to say so. The picker, the Servers count and
///   this rule all read the same folder list, so a miss means the folder really is gone.
enum NativeModelChoice {
    static func resolve(
        installed: [NativeInstalledModel],
        requestedID: String?,
        activeID: String?
    ) -> NativeInstalledModel? {
        let requested = requestedID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard requested.isEmpty || requested == MLXNativeProvider.modelID else {
            return installed.first(where: { $0.id == requested })
        }
        if let active = activeID,
           let match = installed.first(where: { $0.id == active }) {
            return match
        }
        return installed.first
    }
}
