import Foundation

/// The multi-step runtime: ask the model, run what it calls, answer it back, ask again — until the
/// model gives an answer with no call in it, or the step bound is spent.
///
/// Three rules hold it honest:
/// - **The bound is real.** `ToolLoopPolicy` caps the round trips, and the cap is checked after the
///   step that used its slot, so a confused model cannot spend the user's battery re-issuing one
///   call. When the bound ends a turn, the answer is what the last step said plus a line naming the
///   bound as the cause — never silence, never a fabricated wrap-up.
/// - **Failures go back to the model as text.** A typed failure is a result the model may correct
///   itself against. Nothing is swallowed, and a failure the model cannot act on (a tool that is off,
///   a blocked target) stops the loop instead of burning the remaining budget.
/// - **The prompt format buffers its step.** A model writing the fallback protocol puts the call in
///   with the prose, so Cairn cannot show text it has not yet decided is not markup; that format
///   surfaces its answer once the step ends, while a native one streams as it arrives.
public enum ToolLoop {

    public static func stream(
        request: GenerationRequest,
        engine: ToolLoopEngine,
        registry: ToolRegistry,
        format: ToolCallingProtocol,
        policy: ToolLoopPolicy = .default,
        context: ToolExecutionContext,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> AsyncThrowingStream<ToolLoopEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let outcome = try await run(
                        request: request, engine: engine, registry: registry, format: format,
                        policy: policy, context: context, now: now
                    ) { event in continuation.yield(event) }
                    continuation.yield(.completed(outcome))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func run(
        request: GenerationRequest,
        engine: ToolLoopEngine,
        registry: ToolRegistry,
        format: ToolCallingProtocol,
        policy: ToolLoopPolicy,
        context: ToolExecutionContext,
        now: @escaping @Sendable () -> Date,
        emit: @escaping @Sendable (ToolLoopEvent) -> Void
    ) async throws -> ToolLoopOutcome {
        var messages = request.messages
        var run = ToolRun(protocolUsed: format)
        var stepsTaken = 0
        var answer = ""
        var thinking = ""
        var metrics: GenerationMetrics?
        var stoppedAtLimit = false

        while true {
            try Task.checkCancellation()
            stepsTaken += 1
            var stepText = ""
            var buffered = ""
            var calls: [ToolCallRequest] = []

            // Every step carries the tools and the protocol the turn was assembled with, not only the
            // first step. A native backend reads its `tools` array per request, so a second step that
            // arrives without one is a model that was told tools exist and then shown none — which is
            // how an armed `Tools` chip can look dead against a real server: the first step is answered
            // from the block in the system message, and every step after it has nothing to call.
            let stepRequest = GenerationRequest(
                modelID: request.modelID,
                messages: messages,
                config: request.config,
                tools: request.tools,
                toolProtocol: request.toolProtocol
            )
            for try await chunk in engine.stream(stepRequest) {
                switch chunk {
                case .thinking(let piece): thinking += piece; emit(.thinking(piece))
                case .content(let piece):
                    if format == .prompt { buffered += piece }
                    else { stepText += piece; emit(.content(piece)) }
                case .toolCall(let call): calls.append(call)
                case .metrics(let measured): metrics = measured
                }
            }

            var callText = stepText
            if format == .prompt {
                // The offered names are what make a lenient reader safe: an attribute tag is only a call
                // when the tool was actually offered this turn, so `<b>` in prose or an `<a href="…">` in
                // a pasted link stays prose. Without the list, `parse(_:)` reads only the two strict shapes.
                let parsed = PromptToolProtocol.parse(buffered, offered: stepRequest.tools)
                if parsed.isEmpty {
                    // A tag naming an offered tool is struck out even when it carried nothing executable:
                    // the alternative is putting `<web_search query=…>` markup in front of the user as an
                    // answer. Prose with no markup in it comes back untouched.
                    let prose = PromptToolProtocol.strippedText(buffered, offered: stepRequest.tools)
                    stepText = prose
                    emit(.content(prose))
                } else {
                    calls.append(contentsOf: parsed)
                    callText = buffered
                }
            }

            let parsedCalls = calls.compactMap { ToolCall.parse($0) }
            guard !parsedCalls.isEmpty else { answer = stepText; break }

            messages.append(assistantPayload(text: callText, calls: calls, format: format))
            var outcomes: [ToolOutcome] = []
            for call in parsedCalls {
                var invocation = ToolInvocation.begin(call, at: now())
                emit(.callStarted(invocation))
                let outcome = await registry.execute(call, context: context)
                invocation.finish(outcome)
                emit(.callFinished(invocation))
                run.record(invocation)
                outcomes.append(outcome)
            }
            messages.append(contentsOf: resultPayloads(outcomes, format: format))

            let worthContinuing = outcomes.allSatisfy {
                policy.shouldContinue(after: $0, stepsTaken: stepsTaken)
            }
            guard worthContinuing else { answer = stepText; break }
            guard policy.mayRunAnotherStep(stepsTaken: stepsTaken) else {
                stoppedAtLimit = true
                answer = stepText
                break
            }
        }

        run.stepsUsed = stepsTaken
        run.stoppedAtStepLimit = stoppedAtLimit
        if stoppedAtLimit {
            answer = [
                answer,
                "Stopped after \(stepsTaken) tool steps — the step limit for this chat.",
            ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return ToolLoopOutcome(
            text: answer,
            thinking: thinking.isEmpty ? nil : thinking,
            metrics: metrics,
            run: run
        )
    }

    /// The model's own turn, recorded the way its backend expects to read it back: a native call
    /// travels as structured calls, a prompt-format call travels as the text that wrote it.
    static func assistantPayload(
        text: String, calls: [ToolCallRequest], format: ToolCallingProtocol
    ) -> ChatMessagePayload {
        ChatMessagePayload(
            role: .assistant,
            text: text,
            imageData: [],
            toolCalls: format == .native ? calls : [],
            toolCallID: nil
        )
    }

    /// One payload per result for a native backend, which matches them by call id, and one combined
    /// block for a prompt-format model, which has no id field to match against.
    static func resultPayloads(
        _ outcomes: [ToolOutcome], format: ToolCallingProtocol
    ) -> [ChatMessagePayload] {
        guard !outcomes.isEmpty else { return [] }
        if format == .native {
            return outcomes.map { outcome in
                ChatMessagePayload(
                    role: .user,
                    text: outcome.modelText,
                    imageData: [],
                    toolCalls: [],
                    toolCallID: outcome.callID
                )
            }
        }
        let joined = outcomes.map(\.modelText).joined(separator: "\n\n")
        return [ChatMessagePayload(role: .user, text: joined)]
    }

}
