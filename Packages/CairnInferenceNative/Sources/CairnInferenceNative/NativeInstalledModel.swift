import CairnChatDomain
import Foundation

/// One weights folder this phone holds, as the MLX engine needs to know it.
///
/// The App layer reads the folders — this module never opens a directory — and hands the list over as
/// values. `id` is the repository id rather than a slug of the path because it is what the chat picker
/// shows, what the app persists as the chosen model, and what survives a folder being renamed on disk;
/// `directoryURL` is what gets loaded, and never leaves this module.
///
/// `format` travels with it so the picker can badge a folder by the runtime its own files describe. Two
/// rows that differ only by name read as a duplicate; a badge says why they are not.
public struct NativeInstalledModel: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var directoryURL: URL
    public var format: ModelFormat
    public var sizeBytes: Int64

    public init(
        id: String,
        displayName: String,
        directoryURL: URL,
        format: ModelFormat = .mlx,
        sizeBytes: Int64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.directoryURL = directoryURL
        self.format = format
        self.sizeBytes = sizeBytes
    }

    /// The one-folder shape this engine had before a phone could hold more than one model: a directory
    /// with no repository id attached to it.
    ///
    /// It stays because `init(modelDirectory:)` and `init(directoryResolver:)` are how a test points the
    /// engine at one folder, and because the app group wiring may hand over a path with no manifest. A
    /// folder aimed at by hand is still one model, and it still has to be listable.
    static func unwired(directory: URL) -> NativeInstalledModel {
        NativeInstalledModel(
            id: MLXNativeProvider.modelID,
            displayName: "Installed on-device model",
            directoryURL: directory
        )
    }
}
