import Foundation

/// The rule behind Continue Generation: which answer may be picked up again, and what is said to the
/// model when it is.
///
/// A cut-off answer is not a failed one, and continuing it is not the same act as regenerating it: the
/// user wants the rest of *this* answer. So the node that was stopped is never rewritten — a sibling is
/// appended under the same parent, seeded with what landed, and streams only what comes after. The old
/// answer stays as the branch before it, which is what makes the whole feature reversible.
public enum ChatContinuation {

    /// The wording shown when Continue is offered but nothing can be continued.
    public static let nothingToContinue = "That answer has nothing to continue — Continue needs stopped text, not a finished or failed turn."

    /// True when this node is an answer that stopped short and is worth continuing.
    ///
    /// `.interrupted` is a backgrounding cut-off, `.cancelled` is the user pressing Stop, and a `.complete`
    /// node whose server said `.length` ran out of tokens — that is a reply cut off mid-sentence, which is
    /// the case the product asks for. A `.failed` turn is not continued: its own error is the story, and
    /// starting over is Regenerate's job. A hybrid node is not continued either, because its text was
    /// written from drafts by a second engine and "the rest of it" is not a single stream's continuation.
    public static func canContinue(_ node: ChatNode) -> Bool {
        guard node.role == .assistant, !node.text.isEmpty, !node.kind.isHybrid else { return false }
        switch node.state {
        case .interrupted, .cancelled: return true
        case .complete: return node.metrics?.finishReason == .length
        case .streaming, .failed: return false
        }
    }

    /// The instruction that asks for the rest, sent as a user turn of its own so the model is answering a
    /// request rather than guessing why an assistant message reappeared.
    public static func instruction(for node: ChatNode) -> String {
        """
        Continue the answer above from exactly where it stopped. Do not repeat anything already written; \
        begin with the words that follow the last one. Keep the same tone, structure and formatting, and \
        finish the thought.
        """
    }

    /// The history for a continuation turn: the chain **through** the stopped answer — the question and
    /// everything the user actually walked to reach it — then the continue instruction.
    ///
    /// The instruction node is never saved and never enters the tree: it exists only in the request, so
    /// the transcript keeps the user's question and the answer rather than gaining a message the user
    /// never typed. The empty sibling this turn writes into is deliberately absent — a model asked to
    /// continue continues the answer it can see, not a blank message.
    public static func requestHistory(_ nodes: [ChatNode], stopped node: ChatNode) -> [ChatNode] {
        var history = ChatTree.visiblePath(nodes: nodes, activeLeafID: node.id)
        history.append(
            ChatNode(
                conversationID: node.conversationID,
                parentID: node.id,
                role: .user,
                text: instruction(for: node),
                createdAt: node.createdAt
            )
        )
        return history
    }
}
