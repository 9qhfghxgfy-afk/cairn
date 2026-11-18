import Foundation

/// A parsed tool call: the model's request, with arguments already read as JSON.
public struct ToolCall: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]

    public init(id: String, name: String, arguments: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public var isEmpty: Bool { name.isEmpty }

    /// Reads a wire `ToolCallRequest` into a `ToolCall`.
    ///
    /// Returns nil rather than throwing: an undecodable argument blob from one model is not a turn
    /// failure, it is one call the loop declines and tells the model about.
    public static func parse(_ request: ToolCallRequest) -> ToolCall? {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ToolCall.isLegalName(name) else { return nil }
        let raw = request.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "{}" {
            return ToolCall(id: request.id, name: name, arguments: [:])
        }
        guard let decoded = JSONValue.decode(from: raw),
              let object = decoded.dictionaryValue
        else { return nil }
        return ToolCall(id: request.id, name: name, arguments: object)
    }

    /// Tool names are what a model echoes back; anything outside a plain identifier is a sign the
    /// text it produced was not a call at all.
    public static func isLegalName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        return name.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_"
                || character == "-" || character == "."
        }
    }
}

/// What a tool is allowed to do on this turn, decided before it runs.
///
/// Two separate switches, because they are two separate user decisions: `toolsEnabled` is the chat's
/// `Tools` chip, and `outboundWebAllowed` is the acknowledgement that a named web tool sends the
/// query to a public service. A tool that leaves the device is refused when the second is off, even
/// if the chip is on — the check lives here so no handler has to remember it.
public struct ToolExecutionContext: Sendable, Equatable {
    public var toolsEnabled: Bool
    public var outboundWebAllowed: Bool
    /// How much of a tool's output may reach the model and the card.
    public var outputByteLimit: Int
    /// How many results a search may return. A bound on cost and on prompt growth, not on the user.
    public var searchResultLimit: Int

    public init(
        toolsEnabled: Bool = false,
        outboundWebAllowed: Bool = false,
        outputByteLimit: Int = 6_000,
        searchResultLimit: Int = 5
    ) {
        self.toolsEnabled = toolsEnabled
        self.outboundWebAllowed = outboundWebAllowed
        self.outputByteLimit = max(0, outputByteLimit)
        self.searchResultLimit = max(1, searchResultLimit)
    }

    public static let `default` = ToolExecutionContext()

    /// The context one chat turn runs its tools under.
    ///
    /// The two switches stay separate on purpose: the chat's `Tools` chip arms the loop, and the
    /// outbound acknowledgement is what lets a search query leave the phone. A chat with the chip up
    /// and the acknowledgement down still runs the calculator and still drafts mail; it simply gets no
    /// networked tool, which is the same rule `ToolRegistry` enforces before a handler is built.
    public static func forTurn(
        toolsEnabled: Bool,
        outboundWebAllowed: Bool = false
    ) -> ToolExecutionContext {
        ToolExecutionContext(
            toolsEnabled: toolsEnabled,
            outboundWebAllowed: outboundWebAllowed
        )
    }

    /// Clipped to the byte bound, with the truncation flagged rather than silent — a model that
    /// cannot tell the answer was cut will summarise what it was given as if it were whole.
    public func clip(_ text: String) -> (text: String, truncated: Bool) {
        if text.utf8.count <= outputByteLimit { return (text, false) }
        var kept = ""
        var bytes = 0
        for character in text {
            let size = String(character).utf8.count
            if bytes + size > outputByteLimit - 1 { break }
            kept.append(character)
            bytes += size
        }
        return (kept + "…", true)
    }
}

/// One tool's execution side.
///
/// The seam that keeps networking out of the domain: `CairnChatDomain` declares this and never
/// implements a networked case, so `ToolRegistry` can run a turn without importing URLSession.
/// Handlers live in `CairnProviderRemote` (web) and here (calculator, mail draft).
public protocol ToolExecuting: Sendable {
    var definition: ToolDefinition { get }

    /// Runs one call. Throw `ToolFailure` for a named, typed failure; anything else the registry
    /// reports as `.failed`. Never crash, and never return a partially-built result as success.
    func execute(
        _ call: ToolCall,
        context: ToolExecutionContext
    ) async throws -> ToolOutcome
}
