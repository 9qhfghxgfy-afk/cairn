import Foundation

/// The `(i)` popover copy for one Installed row.
///
/// The copy is in the domain rather than in the row because the same three sentences have to appear in the
/// list, in the detail sheet, and in a test that fails if a row starts explaining a server's disk as though
/// it were this phone's. Every sentence here answers the question a person actually has at that moment:
/// whose bytes are these, and what happens if I press Delete.
extension InstalledModelEntry {
    /// The popover's heading: who holds these bytes.
    public var infoTitle: String {
        switch host {
        case .thisPhone: return "Downloaded by Cairn"
        case .system: return InstalledInventory.appleInfoTitle
        case .remoteServer: return "On " + (sourceName ?? "a server")
        }
    }

    /// The explanation. Each host gets its own because the three differ in the one thing that matters —
    /// whether Delete does anything here at all.
    public var infoText: String {
        switch host {
        case .thisPhone:
            return "Cairn put these files on this iPhone and nothing else reads them. Deleting takes the "
                + "folder and any transfer blocks kept with it. Chats that used this model stay; a later "
                + "turn that asks for it needs a model that is here."
        case .system:
            guard let detail, !detail.isEmpty else {
                return InstalledInventory.appleInfoText
            }
            return InstalledInventory.appleInfoText + " Current status: " + detail + "."
        case .remoteServer:
            let machine = sourceName ?? "the server"
            return "\(machine) reported this model about itself. Cairn did not put it there and has no way "
                + "to take it back — removing it means changing that machine, which is done on that "
                + "machine. What Cairn can do here is stop using it."
        }
    }
}
