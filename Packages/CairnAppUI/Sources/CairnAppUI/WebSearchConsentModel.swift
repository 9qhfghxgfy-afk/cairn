import Foundation
import Observation
import CairnChatDomain

/// The one question a web tool may not answer for the user, held as observable state so a sheet can be the
/// answer.
///
/// `CairnProviderRemote` declares the two seams — `WebSearchConsentRequester` and `WebFetchConsentRequester`
/// — as closures, and the App layer closes them over one of these. That is what makes the two web tools one
/// interruption rather than two, and what keeps `CairnAppUI` from having to import the module that owns
/// `URLSession`: this class speaks in providers, hosts and Bools.
///
/// Four rules, and they are the reason this is an object rather than a `@State` bool somewhere:
///
/// - **A decision already on the record answers without asking.** A stored grant means no sheet; a stored
///   "no" means no sheet either. "No" is an answer, not a prompt to be worn down.
/// - **A provider on the user's own network is never asked about.** It is not a third party, and a sheet
///   that asks nothing trains a person to tap through a warning that does mean something later.
/// - **A sheet closed without an answer is a no.** Dismissal is not permission, so the dismissal path
///   records a denial rather than leaving the question open for the next turn to ask again.
/// - **One sheet answers one question.** Two chats can ask at the same moment, and a second provider's
///   question cannot be answered by a sheet that named the first one — so questions queue, each with its own
///   waiters, and the head is what is drawn.
@Observable @MainActor
public final class WebSearchConsentModel {
    /// A question standing in front of a person.
    ///
    /// `subject` is a provider or a page because the two web tools have different subjects: a search goes to
    /// a row the user configured, a page read goes to a host the model named. The record the answer is filed
    /// under differs for the same reason.
    public struct Prompt: Identifiable {
        public enum Subject: Equatable {
            /// A query about to go to a provider the user configured.
            case provider(WebSearchProviderProfile)
            /// A page address about to be read, named by host because the host is the one fact about the
            /// destination worth reading before agreeing. The path is not, and repeating it would put the
            /// user's browsing into a view that is supposed to be about permission. `secure` says whether the
            /// trip is encrypted, because a sheet that promised https about a plain-http read would be lying
            /// in the one place a person is deciding whether to trust it.
            case page(host: String, secure: Bool)
        }

        public let id = UUID()
        public let subject: Subject

        /// Public so a host outside this module — the App layer, or a test — can render the sheet against a
        /// question it built itself instead of having to wait for a tool to ask one.
        public init(subject: Subject) { self.subject = subject }

        /// The name across the top of the sheet.
        public var subjectName: String {
            switch subject {
            case .provider(let profile): return profile.displayName
            case .page(let host, _): return host
            }
        }

        /// The line that says what leaves, in the same terms for both tools. Nothing else about the
        /// conversation is named, because nothing else leaves.
        public var leavingLine: String {
            switch subject {
            case .provider(let profile):
                return "Your search text, as one request to \(profile.displayName)."
            case .page(let host, true):
                return "One page address — \(host) — read over https."
            case .page(let host, false):
                return "One page address — \(host) — sent as plain http, readable by anything "
                    + "between here and it."
            }
        }

        /// The provider row this question is about, or nil for a page read. The sheet draws the attribution
        /// only when there is one, because a page read has no provider to attribute.
        public var profile: WebSearchProviderProfile? {
            if case .provider(let row) = subject { return row }
            return nil
        }

        public var isSearch: Bool {
            if case .provider = subject { return true }
            return false
        }

        /// A page read that leaves unencrypted. Plaintext is a warning condition and never a silent one, so
        /// the sheet says it in its own sentence rather than burying it in the address line.
        public var plaintextRead: Bool {
            if case .page(_, false) = subject { return true }
            return false
        }
    }

    /// The question being drawn, or nil when no sheet is up.
    public var pending: Prompt?

    private let theme: ThemeModel
    /// The questions waiting their turn behind the one on screen. A single shared answer would let a grant
    /// given for DuckDuckGo answer a question about somebody's public instance, which is the exact drift the
    /// per-provider record exists to prevent — so each question keeps its own waiters.
    private var queue: [Prompt] = []
    private var waiters: [UUID: [CheckedContinuation<Bool, Never>]] = [:]

    public init(theme: ThemeModel) { self.theme = theme }

    public var isAsking: Bool { pending != nil }

    /// The search seam: may this provider receive these words?
    public func allowSearch(provider: WebSearchProviderProfile) async -> Bool {
        switch theme.settings.webSearch.consentDecision(for: provider) {
        case .granted: return true
        case .denied: return false
        case .undecided: return await ask(.provider(provider))
        }
    }

    /// The fetch seam: may a page be read off this device? One answer covers the whole tool, because the
    /// destinations are unbounded and this question is not about a provider the user chose.
    public func allowPageRead(url: URL) async -> Bool {
        switch theme.settings.webFetchAllowed {
        case .some(true): return true
        case .some(false): return false
        case nil: break
        }
        let host = url.host?.lowercased() ?? url.absoluteString
        // Only an explicit `http:` counts as plaintext. A public plain-http host is refused by the fetcher
        // before it ever gets here, so the plain reads that remain are the ones to a private address — and
        // they are the ones worth saying so about.
        let secure = url.scheme?.lowercased() != "http"
        return await ask(.page(host: host, secure: secure))
    }

    /// Answers the question on screen and lets the turns blocked on it continue — only that question. A
    /// queued question about another provider is still unanswered, so it comes up next on its own.
    public func resolve(allow: Bool) {
        guard let prompt = pending else { return }
        pending = nil
        file(prompt, allow: allow)
        resume(prompt.id, with: allow)
        showNext()
    }

    /// Asked, and nobody answered — the sheet was closed. Denial, recorded, so the next turn does not ask
    /// again and the tool keeps answering with the same typed refusal. Closing a warning cannot be the same
    /// as agreeing to it.
    public func declineUnanswered() {
        guard let prompt = pending else { return }
        pending = nil
        file(prompt, allow: false)
        resume(prompt.id, with: false)
        showNext()
    }

    /// Where an answer is filed. A provider answer goes to that row's record, so editing the row's address
    /// into someone else's instance cannot inherit a permission given to the old one. A page answer goes to
    /// the one record for reading pages.
    private func file(_ prompt: Prompt, allow: Bool) {
        switch prompt.subject {
        case .provider(let profile):
            if allow { theme.grantWebSearchConsent(for: profile) }
            else { theme.denyWebSearchConsent(for: profile) }
        case .page:
            theme.setWebFetchAllowed(allow)
        }
    }

    private func ask(_ subject: Prompt.Subject) async -> Bool {
        let prompt = Prompt(subject: subject)
        queue.append(prompt)
        if pending == nil { showNext() }
        return await withCheckedContinuation { continuation in
            waiters[prompt.id, default: []].append(continuation)
        }
    }

    private func showNext() {
        guard pending == nil, !queue.isEmpty else { return }
        pending = queue.removeFirst()
    }

    private func resume(_ id: UUID, with answer: Bool) {
        let waiting = waiters.removeValue(forKey: id) ?? []
        for waiter in waiting { waiter.resume(returning: answer) }
    }
}
