import Foundation

/// A message the model wants the user to send. **A draft, always** — Cairn has no path that sends
/// mail by itself, and that is the whole design of this tool.
///
/// The model writes what it would like the user to send; the system's own composer opens with it
/// filled in; and the only person who can press send is the user, looking at the text. Nothing here
/// touches a network, an SMTP client, or a mail account directly.
public struct MailDraft: Sendable, Equatable, Codable {
    /// A body this long is a model that has lost the plot, not a letter.
    public static let bodyCharacterLimit = 20_000
    public static let subjectCharacterLimit = 512
    public static let recipientLimit = 12

    public var recipients: [String]
    public var subject: String
    public var body: String

    public init(recipients: [String] = [], subject: String = "", body: String = "") {
        self.recipients = recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.recipientLimit)
            .map { $0 }
        self.subject = String(subject.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.subjectCharacterLimit))
        self.body = String(body.prefix(Self.bodyCharacterLimit))
    }

    /// A recipient field is the one thing a draft cannot be shown without.
    public var canPresent: Bool { !recipients.isEmpty }

    public var recipientCount: Int { recipients.count }

    /// The lines the card shows: who, what subject, and how much body — never the body itself, which
    /// the user reads in the composer, not in a transcript.
    public var summaryText: String {
        var parts: [String] = ["to: \(recipients.joined(separator: ", "))"]
        if !subject.isEmpty { parts.append("subject: \(subject)") }
        parts.append("\(body.count) characters of body")
        return parts.joined(separator: "\n")
    }
}

/// The device side of `compose_mail`, declared here so the domain never names UIKit.
///
/// `@MainActor` because a composer is a window, and windows live on the main actor. The
/// implementation lives in `CairnAppUI` behind `MessageUI`; a build or a device with no mail account
/// says so through `isAvailable` rather than presenting an empty sheet.
@MainActor
public protocol MailDraftPresenting: Sendable {
    var isAvailable: Bool { get }
    func present(_ draft: MailDraft)
}

/// A presenter for a build with nowhere to present: reports unavailable, and keeps the draft so a
/// preview or a test can read what the model asked for.
@MainActor
public final class UnavailableMailPresenter: MailDraftPresenting {
    public private(set) var lastDraft: MailDraft?
    public init() {}
    public var isAvailable: Bool { false }
    public func present(_ draft: MailDraft) { lastDraft = draft }
}
