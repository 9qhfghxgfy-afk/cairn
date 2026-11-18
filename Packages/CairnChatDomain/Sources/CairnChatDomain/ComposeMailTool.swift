import Foundation

/// `compose_mail`: turn a model's intent into a draft, hand it to the system composer, and stop.
///
/// The result returned to the model says the draft was **offered**, not sent. That wording is the
/// point: a model told a message was sent will go on summarising a send that never happened, and the
/// user is left holding an unsent draft with no reason to expect one. Nothing here can send; the
/// composer's own send button is the only one, and it is on a screen the user is looking at.
public struct ComposeMailTool: ToolExecuting {
    private let presenter: any MailDraftPresenting

    public init(presenter: any MailDraftPresenting) {
        self.presenter = presenter
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.composeMail,
            blurb: """
                Prepare an email as a draft and show it to the user for review. The user, not you, \
                sends it — and it may be discarded. Say in your reply that the draft is open for \
                review; never state that a message was sent.
                """,
            parameters: ToolParameterSchema(
                properties: [
                    "to": ToolParameter(
                        kind: .stringArray,
                        description: "Recipient addresses, each like name@example.com."
                    ),
                    "subject": ToolParameter(
                        kind: .string,
                        description: "The subject line."
                    ),
                    "body": ToolParameter(
                        kind: .string,
                        description: "The message body, as you would want to read it before sending."
                    ),
                ],
                required: ["to", "body"]
            ),
            // Nothing this tool does reaches a network, so it stays offered with the outbound badge
            // down: presenting text to a user on their own screen is not an outbound request.
            networkClass: .onDevice
        )
    }

    public func execute(
        _ call: ToolCall, context: ToolExecutionContext
    ) async throws -> ToolOutcome {
        let draft = Self.draft(from: call.arguments)
        guard draft.canPresent else {
            throw ToolFailure(
                .badArguments,
                detail: "A draft needs at least one recipient in the \"to\" argument."
            )
        }
        guard await presenter.isAvailable else {
            throw ToolFailure(
                .unavailable,
                detail: "This device has no mail account configured, so no composer can open."
            )
        }
        await presenter.present(draft)
        return .success(
            callID: call.id,
            toolName: call.name,
            output: """
                Draft offered to the user for review: \(draft.summaryText)
                It has not been sent. Tell the user it is open for them to check and send.
                """
        )
    }

    /// Accepts `to` as an array, a single address, or a comma-separated string, because a model with
    /// the right address in hand will pick any of the three.
    static func draft(from arguments: [String: JSONValue]) -> MailDraft {
        var recipients: [String] = []
        if case .array(let values)? = arguments["to"] {
            recipients = values.compactMap(\.coercedText)
        } else if case .text(let single)? = arguments["to"] {
            recipients = single.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { String($0) }
        }
        return MailDraft(
            recipients: recipients,
            subject: arguments["subject"]?.coercedText ?? "",
            body: arguments["body"]?.coercedText ?? ""
        )
    }
}
