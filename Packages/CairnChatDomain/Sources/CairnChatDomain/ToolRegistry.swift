import Foundation

/// The tools a turn may use, and the only place a call is ever run.
///
/// Deliberately not `@MainActor` and deliberately not able to reach a socket: the registry holds
/// `any ToolExecuting`, a protocol this module defines and never implements with networking. That is
/// what lets `ChatSessionModel` drive a multi-step tool loop while `URLSession` stays in
/// `CairnProviderRemote`.
///
/// `execute` never throws. A missing tool, an off switch, and a thrown failure all come back as a
/// typed `ToolOutcome` the loop feeds to the model, because a thrown error would end the turn and
/// throw away the text the model already wrote.
public struct ToolRegistry: Sendable {
    public private(set) var tools: [String: any ToolExecuting]

    public init(tools: [any ToolExecuting] = []) {
        var table: [String: any ToolExecuting] = [:]
        for tool in tools where tool.definition.isWellFormed {
            table[tool.definition.name] = tool
        }
        self.tools = table
    }

    public static let empty = ToolRegistry()

    public var isEmpty: Bool { tools.isEmpty }

    /// Sorted, so the names written into the system prompt are byte-stable between turns.
    public var names: [String] { tools.keys.sorted() }

    public func tool(_ name: String) -> (any ToolExecuting)? { tools[name] }

    public func definition(_ name: String) -> ToolDefinition? { tools[name]?.definition }

    /// The definitions to advertise.
    ///
    /// `allowed` is the chat's live set, not a preference: pass the empty set and this returns
    /// nothing, so a chat without the `Tools` chip sends no `tools` array at all and the model is
    /// never told it has a capability it was not given.
    public func definitions(allowed: Set<String>? = nil) -> [ToolDefinition] {
        names.compactMap { name in
            if let allowed, !allowed.contains(name) { return nil }
            return tools[name]?.definition
        }
    }

    /// Definitions that may actually run under this context — used both to advertise and to refuse,
    /// so the list a model sees can never contain a tool the registry would then decline.
    public func availableDefinitions(context: ToolExecutionContext) -> [ToolDefinition] {
        guard context.toolsEnabled else { return [] }
        return names.compactMap { name in
            guard let definition = tools[name]?.definition else { return nil }
            if definition.requiresPublicInternet && !context.outboundWebAllowed { return nil }
            return definition
        }
    }

    /// Runs one call and always returns a result.
    public func execute(
        _ call: ToolCall,
        context: ToolExecutionContext
    ) async -> ToolOutcome {
        let clock = ContinuousClock()
        let started = clock.now
        func finish(_ outcome: ToolOutcome) -> ToolOutcome {
            var settled = outcome
            settled.durationSeconds = Self.elapsed(from: started, to: clock.now)
            return settled
        }

        guard context.toolsEnabled else {
            return finish(.failure(callID: call.id, toolName: call.name, error: .toolsOff))
        }
        guard let handler = tools[call.name] else {
            return finish(.failure(
                callID: call.id, toolName: call.name, error: .unknownTool,
                detail: "Registered tools: \(names.joined(separator: ", "))."
            ))
        }
        let definition = handler.definition
        if definition.requiresPublicInternet && !context.outboundWebAllowed {
            return finish(.failure(
                callID: call.id, toolName: call.name, error: .internetNotAllowed
            ))
        }
        let missing = definition.parameters.missingRequired(in: call.arguments)
        if !missing.isEmpty {
            return finish(.failure(
                callID: call.id, toolName: call.name, error: .badArguments,
                detail: "Missing required argument(s): \(missing.joined(separator: ", "))."
            ))
        }
        if Task.isCancelled {
            return finish(.failure(callID: call.id, toolName: call.name, error: .cancelled))
        }
        do {
            let outcome = try await handler.execute(call, context: context)
            var settled = outcome
            settled.callID = call.id
            settled.toolName = call.name
            let clipped = context.clip(settled.modelText)
            settled.output = clipped.truncated ? clipped.text : settled.output
            settled.truncated = settled.truncated || clipped.truncated
            return finish(settled)
        } catch is CancellationError {
            return finish(.failure(callID: call.id, toolName: call.name, error: .cancelled))
        } catch let failure as ToolFailure {
            return finish(.failure(
                callID: call.id, toolName: call.name, error: failure.error, detail: failure.detail
            ))
        } catch {
            // Typed metadata only: the error's own description may carry an endpoint or a body.
            return finish(.failure(
                callID: call.id, toolName: call.name, error: .failed,
                detail: String(describing: type(of: error))
            ))
        }
    }

    /// Monotonic clock only — a wall-clock jump must never distort a measured duration.
    static func elapsed(
        from start: ContinuousClock.Instant, to end: ContinuousClock.Instant
    ) -> Double {
        let parts = start.duration(to: end).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
