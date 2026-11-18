import Foundation

/// Why a tool did not produce an answer, as a value.
///
/// Every case is returned **to the model** as the tool result, so each one has to say something a
/// model can act on. Nothing here crashes the turn: a failed call is a typed result on the same
/// assistant node, exactly like a candidate that failed inside a hybrid turn.
public enum ToolError: String, Sendable, Equatable, Codable, CaseIterable {
    /// The model named a tool that is not registered on this turn.
    case unknownTool
    /// Arguments were missing, malformed, or outside the schema.
    case badArguments
    /// The chat has no `Tools` opt-in, so nothing was executed.
    case toolsOff
    /// No search endpoint is usable for this route.
    case searchUnavailable
    /// The request would leave the device and the user has not allowed it.
    case internetNotAllowed
    /// The address resolves to a private or loopback target a fetch may not touch.
    case blockedTarget
    /// The response exceeded the byte bound.
    case responseTooLarge
    /// The call outlived its timeout.
    case timedOut
    /// This device or build cannot perform the call at all.
    case unavailable
    /// The user stopped the turn while the call was in flight.
    case cancelled
    /// The endpoint failed for a reason with no more specific name.
    case failed

    /// Whether re-calling with different arguments could plausibly succeed. The step bound is only
    /// worth spending on a call the model can actually fix.
    public var modelCanRetry: Bool {
        switch self {
        case .unknownTool, .badArguments, .blockedTarget, .timedOut, .failed, .searchUnavailable:
            return true
        case .toolsOff, .internetNotAllowed, .unavailable, .cancelled, .responseTooLarge:
            return false
        }
    }

    /// Shown in the tool card. Short, and never a URL or a response body.
    public var userText: String {
        switch self {
        case .unknownTool: return "That tool is not available on this turn."
        case .badArguments: return "The tool was called with arguments it does not accept."
        case .toolsOff: return "Tools are off for this chat."
        case .searchUnavailable: return "No search endpoint is configured."
        case .internetNotAllowed: return "This tool needs the outbound web opt-in."
        case .blockedTarget: return "That address is on a private network, so it was not fetched."
        case .responseTooLarge: return "The page was larger than the allowed response size."
        case .timedOut: return "The request took too long and was stopped."
        case .unavailable: return "This device cannot perform that call."
        case .cancelled: return "Stopped."
        case .failed: return "The call failed."
        }
    }
}

/// A typed failure a tool handler throws, which the registry converts into a `ToolOutcome`.
///
/// Handlers throw this instead of a bespoke error type so one catch in the registry covers every
/// tool, and so an unexpected error still becomes a named case rather than a lost turn.
public struct ToolFailure: Error, Sendable, Equatable {
    public let error: ToolError
    public let detail: String?

    public init(_ error: ToolError, detail: String? = nil) {
        self.error = error
        // Detail is Cairn's own wording, never a response body or a URL. Truncate it here so a
        // handler cannot grow a tool result without bound by accident.
        self.detail = detail.map { String($0.prefix(280)) }
    }
}

/// What one tool call produced. The only thing a tool may hand back.
public struct ToolOutcome: Sendable, Equatable {
    public var callID: String
    public var toolName: String
    /// Already clipped to the byte bound the context carried.
    public var output: String
    public var error: ToolError?
    public var detail: String?
    public var truncated: Bool
    /// Measured by the registry with a monotonic clock, never estimated.
    public var durationSeconds: Double

    public init(
        callID: String,
        toolName: String,
        output: String = "",
        error: ToolError? = nil,
        detail: String? = nil,
        truncated: Bool = false,
        durationSeconds: Double = 0
    ) {
        self.callID = callID
        self.toolName = toolName
        self.output = output
        self.error = error
        self.detail = detail
        self.truncated = truncated
        self.durationSeconds = durationSeconds
    }

    public var succeeded: Bool { error == nil }

    public static func success(
        callID: String, toolName: String, output: String, truncated: Bool = false
    ) -> ToolOutcome {
        ToolOutcome(callID: callID, toolName: toolName, output: output, truncated: truncated)
    }

    public static func failure(
        callID: String, toolName: String, error: ToolError, detail: String? = nil
    ) -> ToolOutcome {
        ToolOutcome(callID: callID, toolName: toolName, error: error, detail: detail)
    }

    /// The text fed back to the model as this call's result.
    ///
    /// A failure names the failure. A model that receives an empty result fills the gap itself,
    /// which is precisely the invented-tool-result behaviour the tool-guidance block forbids.
    public var modelText: String {
        guard let error else {
            return output.isEmpty ? "(the tool returned no content)" : output
        }
        let reason = detail.flatMap { $0.isEmpty ? nil : $0 } ?? error.userText
        return "Tool \(toolName) did not run: \(reason) (reason: \(error.rawValue))."
    }
}
