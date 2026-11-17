import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why Apple's on-device model can or cannot be used, in Cairn's own words.
///
/// The framework's own reason is surfaced rather than a silent failure: "Apple Intelligence is off"
/// and "this device cannot run it" are different answers with different fixes, and a user who is
/// told neither will assume the app is broken.
///
/// Verified against the shipped SDK rather than assumed: `SystemLanguageModel.default.availability`
/// is `@available(iOS 26.0, *)` and its reason cases are exactly `deviceNotEligible`,
/// `appleIntelligenceNotEnabled`, `modelNotReady`.
public enum AppleModelAvailability: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// This OS has no Foundation Models framework at all.
    case unsupportedOS
    /// Compiled without the framework (a host build, or an SDK that predates it).
    case frameworkAbsent
    /// A reason this build does not know, kept in the framework's own words rather than mapped onto
    /// a wrong one.
    case other(String)

    public var reasonText: String {
        switch self {
        case .available: return "Available on this device"
        case .deviceNotEligible: return "This iPhone is not eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings"
        case .modelNotReady: return "The on-device model is still preparing"
        case .unsupportedOS: return "Requires iOS 26 or later"
        case .frameworkAbsent: return "Not available in this build"
        case .other: return "The on-device model is not available right now"
        }
    }

    public var isUsable: Bool { self == .available }
}

/// Reads availability at runtime. Never cached across a session: Apple Intelligence can be toggled
/// in Settings while Cairn is backgrounded, and `SystemLanguageModel` is observable for exactly
/// this reason.
public enum AppleModelAvailabilityReader {
    public static func current() -> AppleModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return map(SystemLanguageModel.default.availability)
        }
        return .unsupportedOS
        #else
        return .frameworkAbsent
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func map(_ availability: SystemLanguageModel.Availability) -> AppleModelAvailability {
        switch availability {
        case .available: return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .other(String(describing: reason))
            }
        }
    }
    #endif
}
