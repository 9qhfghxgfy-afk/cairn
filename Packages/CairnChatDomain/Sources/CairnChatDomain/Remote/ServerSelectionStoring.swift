import Foundation

/// Persistence boundary for the active-server choice and each server's last model. Implemented
/// in `CairnPersistence`; the domain never knows how it is stored.
///
/// Selection is app state, not server state, so it lives apart from `ServerProfileStoring`: a
/// profile describes a machine, selection describes what the user is pointing at right now.
@MainActor
public protocol ServerSelectionStoring: AnyObject {
    func selection() throws -> ServerSelection
    func saveSelection(_ selection: ServerSelection) throws
}
