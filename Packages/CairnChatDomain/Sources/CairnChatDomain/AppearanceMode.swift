import Foundation

/// How the app should present light versus dark. `system` follows the device; the other two pin it,
/// because a theme with a dark half and a light half is only useful if the user can pick which half.
public enum AppearanceMode: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "Match the device"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
