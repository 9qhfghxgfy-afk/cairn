import Foundation

/// The literal markers a local chat template puts in the token stream.
///
/// The thinking pair is built by concatenation, and this is deliberately not a raw-value enum:
/// a raw value must be a literal, and a literal thinking tag in a source file collides with the
/// reasoning control token of the toolchain that compiles and reviews this code, truncating
/// streams and corrupting diffs. The runtime value is identical — only the spelling in this file
/// differs — which is why reading it here is enough to know exactly what is matched.
public enum DeviceTemplateMarker: CaseIterable {
    case thinkingOpen
    case thinkingClose
    case toolStart
    case toolEnd

    public var text: String {
        switch self {
        case .thinkingOpen: return "<" + "think" + ">"
        case .thinkingClose: return "</" + "think" + ">"
        case .toolStart: return "<tool_call>"
        case .toolEnd: return "</tool_call>"
        }
    }

    /// True for the two markers that open a region rather than close it.
    public var opensRegion: Bool {
        self == .thinkingOpen || self == .toolStart
    }

    /// The marker that ends this region, for an opener; nil for a closer.
    public var closingMarker: DeviceTemplateMarker? {
        switch self {
        case .thinkingOpen: return .thinkingClose
        case .toolStart: return .toolEnd
        case .thinkingClose, .toolEnd: return nil
        }
    }
}