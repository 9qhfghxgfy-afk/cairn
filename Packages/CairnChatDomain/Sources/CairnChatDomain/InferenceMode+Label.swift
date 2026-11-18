import Foundation

/// What a mode is called out loud.
///
/// The words live next to the enum rather than in a view because the same four names are shown on the
/// chat's own mode switcher and in the list of chats, and a second copy of that mapping is a second
/// opinion about what a mode is called — one that can quietly disagree with the first.
public extension InferenceMode {
    var displayName: String {
        switch self {
        case .onDeviceOnly: return "On device"
        case .remoteOnly: return "Remote"
        case .hybridParallel: return "Hybrid parallel"
        case .hybridSynthesized: return "Hybrid synthesized"
        }
    }
}
