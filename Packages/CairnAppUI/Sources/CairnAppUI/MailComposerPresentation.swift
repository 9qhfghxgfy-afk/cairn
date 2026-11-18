import Foundation
import CairnChatDomain

#if canImport(UIKit) && canImport(MessageUI)
import MessageUI
import UIKit

/// Opens a model's draft in the system's own mail composer — and does nothing else.
///
/// This is the whole of Cairn's mail story, and it is deliberate. There is no mail account in the app,
/// no SMTP path, and no code here that can send: the composer Apple provides opens with the draft
/// filled in, and the only send button belongs to a screen the user is looking at. A model told a
/// message was "sent" will keep reporting a send that never happened, which is why `ComposeMailTool`
/// answers "offered for review" rather than anything stronger.
///
/// The composer is presented from the top-most view controller of the active scene, because a tool call
/// finishes while the user is looking at whatever sheet the chat left open — a draft that appears behind
/// it reads as a failure to open at all.
///
/// The delegate conformance is marked `@preconcurrency` because MessageUI predates Swift's isolation
/// annotations: `MFMailComposeViewControllerDelegate` is nonisolated, while everything presenting and
/// dismissing a composer has to do lives on the main actor. Apple delivers these callbacks on the main
/// thread, so the isolation this class claims is the isolation the callback really arrives on — the
/// attribute records that fact rather than opening a race. Swift 6 otherwise refuses the conformance
/// outright (CI run 44239762797, and this branch never compiled on the host lane because MessageUI does
/// not exist on macOS).
@MainActor
public final class MailComposerPresentation:
    NSObject, MailDraftPresenting, @preconcurrency MFMailComposeViewControllerDelegate {
    public override init() { super.init() }

    public var isAvailable: Bool { MFMailComposeViewController.canSendMail() }

    public func present(_ draft: MailDraft) {
        guard draft.canPresent, isAvailable, let host = Self.hostViewController() else { return }
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        composer.setToRecipients(draft.recipients)
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        Self.attachPopover(of: composer, to: host)
        host.present(composer, animated: true)
    }

    /// Whatever the user did with it — sent, saved as a draft, or discarded — the composer closes and
    /// Cairn keeps no record of the choice. That is the tool's honest limit, and the transcript says the
    /// draft was offered rather than implying an outcome.
    public func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: (any Error)?
    ) {
        controller.dismiss(animated: true)
    }

    /// On iPad a modal without a popover anchor is a crash, and a crash would mean the user never sees
    /// the draft they asked for. Centred, with no arrow, is the shape that works on every size.
    private static func attachPopover(of composer: MFMailComposeViewController, to host: UIViewController) {
        guard let popover = composer.popoverPresentationController else { return }
        popover.sourceView = host.view
        popover.sourceRect = CGRect(
            x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1
        )
        popover.permittedArrowDirections = []
    }

    /// The top-most controller of the scene in front, falling back to any scene when none reports itself
    /// active — which happens in the moment between background and foreground, when a tool can still
    /// finish.
    private static func hostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

#else

/// A build with no mail composer on it — a Mac host build, or one where MessageUI is unavailable.
///
/// Reports unavailable rather than pretending, so `compose_mail` answers "this device cannot do that"
/// instead of opening nothing. The draft is kept on the object so a preview or a test can still read what
/// the model asked for.
@MainActor
public final class MailComposerPresentation: MailDraftPresenting {
    public private(set) var lastDraft: MailDraft?

    public init() {}

    public var isAvailable: Bool { false }

    public func present(_ draft: MailDraft) { lastDraft = draft }
}

#endif
