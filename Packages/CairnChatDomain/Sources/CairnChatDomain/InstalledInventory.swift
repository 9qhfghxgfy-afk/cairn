import Foundation

/// Assembles the Installed section from the three sources that really exist.
///
/// Each source answers a different question and only one of them was ever asked. The phone's own store
/// knows what Cairn downloaded; Apple's framework knows whether the system model is usable; a server
/// knows what it holds. Showing any one of the three alone is what made the tab read as "no models" on a
/// phone with gigabytes on disk, and merging them naively is what would let a server's `qwen3:4b`
/// overwrite the phone's folder of the same name — so the merge keys on the host name-spaced `id` and
/// keeps every distinct entry.
///
/// Pure on purpose: nothing here opens a file or a socket, which is the only reason the merge rule below
/// is a test rather than a screenshot.
public enum InstalledInventory {
    /// The built-in model's name and the explanation its `(i)` popover carries.
    ///
    /// The sentence has to say three things or it answers none of them: that the model is part of iOS,
    /// that no download is needed here, and that the reason it can be missing is a Settings switch or
    /// the hardware rather than anything Cairn failed to do.
    public static let appleDisplayName = "Apple Intelligence"
    public static let appleInfoTitle = "Built into iOS"
    public static let appleInfoText = """
        This model is part of iOS. Apple installs it, updates it and decides when to take it out of \
        memory, so there is nothing to download here and no folder for Cairn to delete. What it costs \
        your storage is Apple's to report, not Cairn's.
        """

    /// The phone's own folders, read from its manifests.
    ///
    /// Order is kept as handed over — newest first, the order the store reports — because a phone holding
    /// two builds of one family should show the one it got last at the top.
    public static func entries(for rows: [InstalledLocalModel]) -> [InstalledModelEntry] {
        rows.map { row in
            InstalledModelEntry(
                id: InstalledModelEntry.phoneID(repoID: row.repoID),
                displayName: row.displayName,
                format: row.format,
                host: .thisPhone,
                hostModelID: row.repoID,
                sizeBytes: row.sizeBytes > 0 ? row.sizeBytes : nil,
                fileCount: row.fileCount,
                installedOn: row.installedOn
            )
        }
    }

    /// The built-in system model, or nil when this device cannot run it.
    ///
    /// A model that is not available is absent from the list rather than present and greyed: the Servers
    /// screen already carries the reason in the runtime's own words, and a row that offers a model this
    /// phone cannot run is a tap that fails.
    public static func appleIntelligence(available: Bool, reason: String) -> InstalledModelEntry? {
        guard available else { return nil }
        return InstalledModelEntry(
            id: InstalledModelEntry.systemID,
            displayName: appleDisplayName,
            format: .appleIntelligence,
            host: .system,
            detail: reason
        )
    }

    /// One server's own list, keyed to that server.
    ///
    /// Nothing is added to these entries and none of their fields is inferred — the server published a
    /// name and maybe a parameter size, and that is what the row says.
    public static func entries(
        for models: [ModelInfo],
        profileID: String,
        serverName: String
    ) -> [InstalledModelEntry] {
        models.map { info in
            InstalledModelEntry(
                id: InstalledModelEntry.serverID(profileID: profileID, modelID: info.id),
                displayName: info.displayName,
                format: .server,
                host: .remoteServer,
                hostModelID: info.id,
                sourceName: serverName,
                detail: info.parameterSize
            )
        }
    }

    /// The one list the Installed section draws.
    ///
    /// The groups arrive in the order a person reads them: what this phone holds, then the model iOS
    /// holds, then what a server says it holds — device-owned bytes first, because they are the ones this
    /// app can act on. Dedupe is by `id`, which is host-name-spaced, so the only rows it can ever collapse
    /// are the same row reported twice by the same source; a same-named model on two hosts always survives
    /// as two rows.
    ///
    /// A group that failed to load arrives empty rather than missing: a server that would not answer is
    /// still the phone's own models' list, and a list that drops the phone's folders because a socket
    /// timed out is the bug this whole type exists to fix.
    public static func merge(_ groups: [[InstalledModelEntry]]) -> [InstalledModelEntry] {
        var seen: Set<String> = []
        var merged: [InstalledModelEntry] = []
        for entry in groups.flatMap({ $0 }) {
            guard !seen.contains(entry.id) else { continue }
            seen.insert(entry.id)
            merged.append(entry)
        }
        return merged
    }
}
