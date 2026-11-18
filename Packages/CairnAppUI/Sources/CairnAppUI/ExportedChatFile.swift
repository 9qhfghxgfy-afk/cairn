import Foundation

/// An exported chat, written where a share sheet can pick it up.
///
/// The app's own temporary directory is the only place this lands. Cairn does not keep a second copy of a
/// user's chats somewhere they never chose, and the system is free to clean this up — which is the right
/// answer for bytes whose whole job is to be handed to something else.
struct ExportedChatFile: Identifiable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }

    /// nil when the write fails, which on a full or locked device is a real possibility and has to be a
    /// visible outcome rather than a share sheet with nothing in it.
    static func write(name: String, data: Data) -> ExportedChatFile? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-exports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return ExportedChatFile(name: name, url: url)
        } catch {
            return nil
        }
    }
}
