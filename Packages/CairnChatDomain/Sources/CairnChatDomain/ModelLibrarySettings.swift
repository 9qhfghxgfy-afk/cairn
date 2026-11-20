import Foundation

/// Whether the Models screen offers Cairn's curated download library.
///
/// Held as a field of `AppSettings` rather than as a view default because it decides what the screen
/// offers, and one half of what it offers is a list of names to ask a server for. Cairn's rule is that
/// a person asks for the network rather than finds it switched on, so the library is shown by default
/// and the *download* is the act that carries the outbound badge.
///
/// Stored as an optional for the reason documented on `AppSettings.webTools`: a settings row written
/// before this switch existed must read back as the shipped answer, not fail to decode and take the
/// person's theme and default configuration down with it.
extension AppSettings {
    /// The stored answer with the shipped answer filled in for a row that never wrote the key.
    public var downloadCatalogIsShown: Bool { showsDownloadCatalog ?? true }

    /// Written as a new value rather than in place, so the whole settings row travels to the store the
    /// way every other switch here does and survives a relaunch instead of living in the view.
    public func setDownloadCatalogShown(_ shown: Bool) -> AppSettings {
        var copy = self
        copy.showsDownloadCatalog = shown
        return copy
    }

    /// Whether pulling weights is allowed. Nothing defaults this to true: the acknowledgement is
    /// granted, and a settings row that never granted it means the traffic has not been agreed to.
    public var modelDownloadsAreAllowed: Bool { modelDownloadsAllowed ?? false }

    public func setModelDownloadsAllowed(_ allowed: Bool) -> AppSettings {
        var copy = self
        copy.modelDownloadsAllowed = allowed
        return copy
    }
}
