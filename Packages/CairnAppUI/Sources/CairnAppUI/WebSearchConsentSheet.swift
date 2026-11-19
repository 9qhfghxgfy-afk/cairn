import SwiftUI
import CairnChatDomain

/// The first-use question: may this go out?
///
/// The sheet exists because a tool cannot ask. `web_search` and `web_fetch` run inside a turn, on a
/// background actor, with no window — the App layer hands them a closure, and this is what that closure puts
/// in front of a person.
///
/// What it says is deliberately narrow. It names the subject — the provider the user configured, or the host
/// a page will be read from — and the one thing leaving: the search's words, or the address. It does not
/// offer a different provider, because there is no fallback to offer; a refusal stops the search rather than
/// sending it somewhere else. And it says what happens after, because a permission whose consequence is
/// invisible is a formality.
///
/// Both buttons are real. Dismissing the sheet without choosing records a denial rather than leaving the
/// question open, so closing a warning cannot be the same as agreeing to it.
struct WebSearchConsentSheet: View {
    let model: WebSearchConsentModel
    let prompt: WebSearchConsentModel.Prompt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .font(.headline)
                        Text(prompt.leavingLine)
                            .font(.callout)
                        Text(disclosure)
                            .font(.footnote)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(prompt.subjectName)
                }

                Section("What changes if you allow it") {
                    Label(
                        "A badge stays up while search can leave this device.",
                        systemImage: "globe.badge.chevron.backward"
                    )
                    Label(
                        "Nothing from this conversation travels with the request — no transcript, "
                            + "no attachments, no cookies.",
                        systemImage: "lock.shield"
                    )
                    if let profile = prompt.profile,
                       let note = WebSearchAttribution.note(for: profile.kind) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                }

                Section {
                    Button(action: allow) {
                        Text(allowTitle).fontWeight(.semibold)
                    }
                    .tint(CairnTheme.amber)

                    Button(role: .destructive, action: deny) {
                        Text("Don't allow it")
                    }
                } footer: {
                    Text(footerText)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            .navigationTitle(prompt.isSearch ? "Allow web search?" : "Read this page?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { deny() }
                }
            }
        }
        // Closing the sheet is a refusal, not a way to postpone the decision. A dismissed warning that left
        // the question undecided would simply bring the sheet back next turn, which teaches a person that
        // warnings can be swiped away.
        .interactiveDismissDisabled()
    }

    private var headline: String {
        prompt.isSearch
            ? "Cairn is about to send a search to \(prompt.subjectName)."
            : "Cairn is about to read a page off this device."
    }

    /// What leaves, in the module's own words for a provider — and a plain sentence for a page, which has no
    /// provider behind it to attribute anything to.
    private var disclosure: String {
        guard let profile = prompt.profile else {
            return prompt.plaintextRead
                ? "One plain-http request for the address, and whatever the page answers. Anyone on that "
                    + "path can read it. The rest of this conversation stays here."
                : "One https request for the address, and whatever the page answers. The rest of this "
                    + "conversation stays here."
        }
        return WebSearchAttribution.disclosure(for: profile.kind)
    }

    private var allowTitle: String {
        prompt.isSearch ? "Allow this search" : "Allow page reading"
    }

    private var footerText: String {
        let whereToChange = prompt.isSearch
            ? "Settings ‹ Tools ‹ Web Search"
            : "Settings ‹ Tools"
        return prompt.isSearch
            ? "You can change this later in \(whereToChange). If you say no, searching stops with that "
                + "answer rather than sending your words somewhere else."
            : "You can change this later in \(whereToChange). If you say no, the tool answers that it cannot "
                + "read the page, and the model is told that rather than given an invented answer."
    }

    private func allow() {
        model.resolve(allow: true)
        dismiss()
    }

    private func deny() {
        model.resolve(allow: false)
        dismiss()
    }
}
