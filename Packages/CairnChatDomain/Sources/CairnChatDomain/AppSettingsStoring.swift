import Foundation

/// Persistence boundary for app-wide settings, including the default chat configuration.
///
/// Implemented in `CairnPersistence`; `CairnAppUI` reaches it only through a model object, because
/// views may not touch a store. One getter/setter pair on purpose: the settings are one small value
/// that is always read and written whole, so a partial write could leave a default configuration
/// disagreeing with the theme beside it.
@MainActor
public protocol AppSettingsStoring: AnyObject {
    func appSettings() throws -> AppSettings
    func saveAppSettings(_ settings: AppSettings) throws
}
