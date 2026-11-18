import Foundation
import CairnChatDomain

/// Stitches streamed `tool_calls` fragments into whole calls.
///
/// The SSE dialect splits one call across chunks: the id and name in the first fragment, the
/// arguments in pieces after it. No single event says a call has ended, so the stitching lives here
/// and the pipeline decides when to ask for the result — at the choice's finish reason, and again
/// when the stream ends for a server that never sends one.
///
/// Keyed by the dialect's own `index` rather than by id, because many servers leave the id off every
/// fragment but the first. Order is preserved, so the loop and the cards see the calls in the order
/// the model wrote them.
struct RemoteToolCallStitcher: Sendable {
    private struct Fragment: Sendable {
        var id: String
        var name: String
        var arguments: String
    }

    private var parts: [Int: Fragment] = [:]
    private var order: [Int] = []

    var isEmpty: Bool { parts.isEmpty }

    mutating func feed(index: Int, id: String?, name: String?, arguments: String) {
        if parts[index] == nil { order.append(index) }
        var entry = parts[index] ?? Fragment(id: "", name: "", arguments: "")
        if let id, !id.isEmpty { entry.id = id }
        if let name, !name.isEmpty { entry.name += name }
        entry.arguments += arguments
        parts[index] = entry
    }

    /// The calls gathered so far, in the order each first appeared, cleared as they are handed over —
    /// so a flush cannot emit the same call twice.
    ///
    /// A fragment set with no name is dropped rather than guessed at: an argument blob with nothing to
    /// run is not a call, and inventing a name would run a tool the model never asked for.
    mutating func flush() -> [ToolCallRequest] {
        defer { parts.removeAll(); order.removeAll() }
        return order.compactMap { index in
            guard let entry = parts[index], !entry.name.isEmpty else { return nil }
            return ToolCallRequest(
                id: entry.id.isEmpty ? "call-\(index)" : entry.id,
                name: entry.name,
                argumentsJSON: entry.arguments.isEmpty ? "{}" : entry.arguments
            )
        }
    }
}
