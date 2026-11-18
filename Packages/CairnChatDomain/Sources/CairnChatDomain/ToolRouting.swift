import Foundation


/// Which tools a turn gets, and in which format.
///
/// Three facts decide it, and they are all data the app already holds: the user's `Tools` chip, the
/// per-tool toggles, and what the connected backend says it can do. Nothing is guessed about a
/// server, and the chip's meaning stays single — tools on means the model is offered the tools that
/// are switched on, and tools off means no tool appears in the prompt at all.
public struct ToolRouting: Sendable {
    public var toolToggle: ToolToggleSet
    public var capabilities: ProviderCapabilities
    public var registry: ToolRegistry
    /// Whether a tool on this turn may send its argument to a public service — the app-wide outbound
    /// acknowledgement the `Tools` chip's disclosure obtains. Without it a web tool is **not offered
    /// at all** rather than offered and then declined: a model told it has a tool it cannot run writes
    /// an answer from a call it never made.
    public var outboundWebAllowed: Bool

    public init(
        toolToggle: ToolToggleSet,
        capabilities: ProviderCapabilities,
        registry: ToolRegistry,
        outboundWebAllowed: Bool = false
    ) {
        self.toolToggle = toolToggle
        self.capabilities = capabilities
        self.registry = registry
        self.outboundWebAllowed = outboundWebAllowed
    }

    /// Whether this turn is a tool turn at all.
    public var offersTools: Bool { toolToggle.isEnabled && !registry.isEmpty }

    public var format: ToolCallingProtocol {
        guard offersTools else { return .none }
        return capabilities.toolCalling ? .native : .prompt
    }

    /// The tools this turn could actually run: switched on, registered, and — for a tool that would
    /// reach the public internet — covered by the outbound acknowledgement. One list feeds both the
    /// offer and the refusal in `ToolRegistry.execute`, so the set a model sees can never contain a
    /// tool the registry would then decline.
    public var offerableNames: [String] {
        toolToggle.enabledToolNames.filter { name in
            guard let definition = registry.definition(name) else { return false }
            return outboundWebAllowed || !definition.requiresPublicInternet
        }
    }

    /// The tools to offer, fitted to the remaining context budget.
    ///
    /// The whole block is measured rather than each definition on its own, because what actually goes
    /// into the prompt is one block: individually-fitting definitions can still overflow together, and
    /// the prompt is what must fit. Definitions that do not fit are dropped **oldest-name-first** so
    /// the set a model sees is stable across turns, and the dropped names come back so the UI can say
    /// which tools were left out rather than let a tool quietly vanish.
    public func selection(withinWordBudget budget: Int, wordBudget: (String) -> Int) -> ToolSelection {
        guard offersTools else { return ToolSelection() }
        let enabled = offerableNames.compactMap { name in
            registry.definition(name)
        }
        var kept: [ToolDefinition] = []
        var dropped: [String] = []
        var used = 0
        for definition in enabled {
            let block = ToolPromptBlock.render(kept + [definition])
            let cost = wordBudget(block)
            if cost <= budget {
                kept.append(definition)
                used = cost
            } else {
                dropped.append(definition.name)
            }
        }
        _ = used
        return ToolSelection(definitions: kept, droppedNames: dropped)
    }
}

/// What one turn was offered, plus what had to be left out.
public struct ToolSelection: Sendable, Equatable {
    public var definitions: [ToolDefinition]
    public var droppedNames: [String]

    public init(definitions: [ToolDefinition] = [], droppedNames: [String] = []) {
        self.definitions = definitions
        self.droppedNames = droppedNames
    }

    public var isEmpty: Bool { definitions.isEmpty }

    /// The protocol block for this selection — empty when nothing is offered, which is the only way
    /// "tools off" can be guaranteed to leave nothing in the prompt.
    public func instruction(format: ToolCallingProtocol) -> String {
        guard format != .none else { return "" }
        return ToolPromptBlock.render(definitions, format: format)
    }
}
