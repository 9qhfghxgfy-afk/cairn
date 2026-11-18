import Foundation

/// Everything one turn's tool use amounts to: the calls, how many round trips they took, and which
/// protocol carried them.
///
/// One value written whole, in its own column, for the same reason `HybridProvenance` is: several
/// related facts about a single node that would otherwise make every added field a schema migration.
/// A node with no tools has no `ToolRun` at all, which is how a pre-P3 row keeps reading as
/// "no tools ran" rather than "zero tools ran, somehow".
public struct ToolRun: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var protocolUsed: ToolCallingProtocol
    public var invocations: [ToolInvocation]
    /// Model calls made this turn, counting the one that produced the final text.
    public var stepsUsed: Int
    /// True when the turn ended because the step bound was reached with calls still outstanding —
    /// stated, never inferred by the UI from a count.
    public var stoppedAtStepLimit: Bool
    public var startedAt: Date

    public init(
        id: UUID = UUID(),
        protocolUsed: ToolCallingProtocol,
        invocations: [ToolInvocation] = [],
        stepsUsed: Int = 0,
        stoppedAtStepLimit: Bool = false,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.protocolUsed = protocolUsed
        self.invocations = invocations
        self.stepsUsed = stepsUsed
        self.stoppedAtStepLimit = stoppedAtStepLimit
        self.startedAt = startedAt
    }

    /// Inserts or replaces by call id, so a card can appear as `.running` and then be settled in
    /// place rather than being appended twice.
    public mutating func record(_ invocation: ToolInvocation) {
        if let index = invocations.firstIndex(where: { $0.id == invocation.id }) {
            invocations[index] = invocation
        } else {
            invocations.append(invocation)
        }
    }

    public func invocation(id: String) -> ToolInvocation? {
        invocations.first { $0.id == id }
    }

    public var isEmpty: Bool { invocations.isEmpty }
    public var callCount: Int { invocations.count }

    /// True when anything in this run reached the public internet — the condition the persistent
    /// outbound badge keys on, and the one thing a user must be able to see after the turn ends.
    public var usedWebTools: Bool { invocations.contains { $0.isWebTool } }

    public var failedCount: Int {
        invocations.filter { $0.state == .failed || $0.state == .cancelled }.count
    }

    public var isStillRunning: Bool { invocations.contains { $0.state == .running } }

    /// The header line above the cards: what ran, how long the loop took in round trips, and whether
    /// it was cut short.
    public var summaryText: String {
        var parts: [String] = ["\(callCount) tool call" + (callCount == 1 ? "" : "s")]
        parts.append("\(stepsUsed) step" + (stepsUsed == 1 ? "" : "s"))
        parts.append(protocolUsed.label)
        if stoppedAtStepLimit { parts.append("stopped at the step limit") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return parts.joined(separator: " · ")
    }
}
