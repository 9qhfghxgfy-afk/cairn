import Foundation
import CairnChatDomain

/// The Installed tab's own half of `ModelManagerModel`: read the phone, merge, and take a model back.
///
/// Kept apart from the file that holds the server's half because the two answer different questions and
/// because the merge rule is the point of this feature: a list built from one source is the bug being
/// fixed, and a view model that reads three sources in one place is where that rule has to live.
extension ModelManagerModel {
    /// Whether this build can see the phone's own model store at all. The empty-list copy reads this so a
    /// build with no store says "this build cannot reach its model store" rather than "you have no models".
    public var servingLocalModels: Bool { installedServing != nil }

    /// The rule applied to one row, so a view draws a control **or** a reason and never both.
    public func deletionVerdict(for entry: InstalledModelEntry) -> ModelDeletionVerdict {
        ModelDeletion.verdict(for: entry)
    }

    /// Re-reads every source and rebuilds the one list.
    ///
    /// The phone is read first and the server's rows are folded in from `installed`, which the caller has
    /// just refreshed. A store that refuses does not empty the tab: the server's rows stay, with the
    /// refusal as the notice, because "this phone holds nothing" is a claim the refusal disproves rather
    /// than supports.
    public func refreshInstalledEntries() async {
        guard let serving = installedServing else {
            installedEntries = remoteInstalledEntries
            return
        }
        let local: [InstalledModelEntry]
        do {
            local = try await serving.installedEntries()
        } catch {
            // The rows already on screen are kept. A store that will not read is not evidence that the
            // phone's folders have gone — that is the same rule the Running tab follows, and it is what
            // keeps a refusal during a refresh from emptying the tab under a person's hands.
            local = installedEntries.filter { $0.host != .remoteServer }
            notice = error.localizedDescription
        }
        installedEntries = InstalledInventory.merge([local, remoteInstalledEntries])
    }

    /// Takes one model back and re-reads everything that its removal changes.
    ///
    /// The order is the order the facts have to be true in: the service unloads and deletes, the App layer
    /// re-reads the on-device engine report and the Download list, and only then does this list redraw. A
    /// removal that throws leaves every list as it was — the row is still there, which is the only honest
    /// answer to a delete that did not happen.
    public func removeInstalled(_ entry: InstalledModelEntry) async {
        guard let serving = installedServing else {
            notice = InstalledModelError.storageUnavailable.errorDescription
            return
        }
        do {
            try await serving.remove(entry)
            await onLocalModelRemoved?(entry)
        } catch let issue as InstalledModelError {
            notice = issue.errorDescription
        } catch {
            notice = error.localizedDescription
        }
        await refreshInstalledEntries()
    }

    /// Asks the open server about one of its own rows.
    ///
    /// Only a server row can be asked about: a folder on this phone has no detail endpoint, and calling the
    /// server with a phone repository id would show whatever that server happens to hold under a similar
    /// name as though it described the bytes on this device. A row with no host id is not a server's, and
    /// this returns without asking.
    public func inspectRemote(_ entry: InstalledModelEntry) async {
        guard entry.host == .remoteServer, let hostModelID = entry.hostModelID else { return }
        await inspect(hostModelID)
    }

    /// The open server's rows, keyed to that server.
    ///
    /// Empty until a profile is open and that profile has answered. Nothing here reaches for a server that
    /// is not the one in front of the person, and nothing here is inferred about a machine they did not
    /// choose.
    private var remoteInstalledEntries: [InstalledModelEntry] {
        guard let profile else { return [] }
        return InstalledInventory.entries(
            for: installed,
            // The profile's `id` is a UUID and the entry key is a string, so the key is spelled the way
            // every other UUID-keyed identifier in Cairn spells it — `uuidString`, as in `RemoteEngineID`
            // and the Keychain account name — which is also what a server row's id prints as.
            profileID: profile.id.uuidString,
            serverName: profile.name
        )
    }
}
