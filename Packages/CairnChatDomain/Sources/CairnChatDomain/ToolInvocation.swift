import Foundation

/// How a model reached a tool on this turn.
///
/// Two ways exist and they are not interchangeable: a backend with documented function calling gets
/// a `tools` array and returns structured calls, and a backend without it gets an instruction block
/// and returns text Cairn parses under a bound. The UI says which one ran, because "the model used a
/// tool" means something different when the call was parsed out of prose.
public enum ToolCallingProtocol: String, Sendable, Equatable, Codable, CaseIterable {
    case native
    case prompt
    /// Nothing was offered this turn, so nothing could be called. It is a case rather than a nil so
    /// the routing decision and the record of a turn speak one type.
    case none

    public var label: String {
        switch self {
        case .native: return "native tool calling"
        case .prompt: return "prompt tool protocol"
        case .none: return "no tools"
        }
    }

    /// Whether a turn on this format has to be told the call shapes in its system block. Only a
    /// native backend does not, and only because its request already carries the schemas.
    public var needsPromptInstruction: Bool { self == .prompt }
}

/// Where one tool call got to.
public enum ToolInvocationState: String, Sendable, Equatable, Codable, CaseIterable {
    case running
    case complete
    case failed
    case cancelled
}

/// One executed tool call, as the user sees it and as it is stored on the assistant node.
///
/// This is the record behind the collapsible card: name, arguments, output, duration, typed failure.
/// It lives on the **one** assistant node rather than as its own tree nodes, because a tool call is
/// part of the answer it fed, the same way a hybrid node's drafts are part of its answer.
public struct ToolInvocation: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    /// Cairn's own rendering of the arguments, not the model's raw blob, so a card is readable even
    /// when the model emitted badly-formatted JSON.
    public var argumentsText: String
    public var output: String
    public var error: ToolError?
    public var detail: String?
    /// Measured by the registry; nil until the call finishes, because a duration for a call that has
    /// not returned is not a measurement.
    public var durationSeconds: Double?
    public var truncated: Bool
    public var state: ToolInvocationState
    public var startedAt: Date

    public init(
        id: String,
        name: String,
        argumentsText: String = "",
        output: String = "",
        error: ToolError? = nil,
        detail: String? = nil,
        durationSeconds: Double? = nil,
        truncated: Bool = false,
        state: ToolInvocationState = .running,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.argumentsText = argumentsText
        self.output = output
        self.error = error
        self.detail = detail
        self.durationSeconds = durationSeconds
        self.truncated = truncated
        self.state = state
        self.startedAt = startedAt
    }

    /// The card's opening line, before the call has a result.
    public static func begin(_ call: ToolCall, at date: Date = Date()) -> ToolInvocation {
        ToolInvocation(
            id: call.id.isEmpty ? call.name : call.id,
            name: call.name,
            argumentsText: Self.renderArguments(call.arguments),
            startedAt: date
        )
    }

    /// Applies a finished outcome, in one move, so a card cannot show a result with a stale state.
    public mutating func finish(_ outcome: ToolOutcome) {
        output = outcome.output
        error = outcome.error
        detail = outcome.detail
        truncated = outcome.truncated
        durationSeconds = outcome.durationSeconds
        if outcome.error == .cancelled {
            state = .cancelled
        } else {
            state = outcome.succeeded ? .complete : .failed
        }
    }

    public var isWebTool: Bool { BuiltInTool.isWebTool(name) }
    public var succeeded: Bool { error == nil && state == .complete }

    /// `key: value` per line, sorted. The card reads this; the model never does.
    public static func renderArguments(_ arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else { return "" }
        return arguments.keys.sorted().map { key in
            let rendered = arguments[key]?.coercedText ?? arguments[key]?.prettyText ?? ""
            return "\(key): \(rendered)"
        }.joined(separator: "\n")
    }

    /// "0.42 s" / "1.8 s" — one place, so the card and the transcript agree on how a duration reads.
    public var durationText: String? {
        guard let seconds = durationSeconds else { return nil }
        if seconds < 0.01 { return "<0.01 s" }
        return String(format: "%.2f s", seconds)
    }
}
