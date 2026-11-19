import SwiftUI
import CairnChatDomain

/// The Web Search screen: which provider answers, how many results it returns, whether it works, and what
/// has been agreed to about it.
///
/// It replaces the one text field that used to sit in Settings. A single address could not express which
/// provider is active, could not hold a credential, could not say whether it had been agreed to, and could
/// not be tested — so the screen is a list of rows with one of them selected, which is what the domain
/// actually models.
///
/// What is deliberately *not* here: any way to fall back. A failing provider is a typed failure the tool
/// reports, not an invitation to send the query somewhere the user did not pick.
struct WebSearchSettingsScreen: View {
    let model: WebSearchSettingsModel
    /// Present when this build cannot open a connection at all. The Test button is then absent rather than
    /// disabled — a button that can only say "not available" is a worse affordance than no button.
    private var canTest: Bool { model.testing != nil }
    /// A draft in front of the editor sheet. `WebSearchRowEdit` carries an optional id of its own — a row
    /// being added has none yet — so the sheet needs a separate identity to present on.
    @State private var editing: RowDraft?
    @State private var showingGuide = false

    /// One row draft, wrapped so SwiftUI can present it as a sheet item.
    struct RowDraft: Identifiable {
        let id = UUID()
        var draft: WebSearchRowEdit
    }

    init(model: WebSearchSettingsModel) {
        self.model = model
    }

    var body: some View {
        Form {
            if let notice = model.revertNoticeText {
                WebSearchRevertNoticeRow(notice: notice) { model.dismissRevertNotice() }
            }

            activeSection
            providerSection
            resultsSection
            testSection

            // The header goes in as a view, not as `Section("…")`: that initializer takes content only,
            // so a `footer:` trailing clause has nothing to bind to and the compiler reports the title
            // string as a missing `content:` argument.
            Section {
                Button {
                    showingGuide = true
                } label: {
                    Label("How do I set up SearXNG?", systemImage: "questionmark.circle")
                }
                .font(.callout.weight(.semibold))
            } header: {
                Text("Setting up your own instance")
            } footer: {
                footerText
            }
        }
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { rowDraft in
            NavigationStack {
                WebSearchProviderEditor(model: model, draft: rowDraft.draft)
            }
        }
        .sheet(isPresented: $showingGuide) {
            SearxngGuideSheet()
        }
    }

    // MARK: - Which provider

    var activeSection: some View {
        Section {
            Picker(
                selection: Binding(
                    get: { model.active.id },
                    set: { model.select(id: $0) }
                ),
                label: Text("Search provider")
            ) {
                ForEach(model.rows) { row in
                    Text(row.displayName).tag(row.id)
                }
            }
            .pickerStyle(.navigationLink)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.active.kind.setupHint)
                Text(model.active.networkLabel)
                if model.active.usesPlaintext {
                    Text("Plaintext — the query leaves this device unencrypted.")
                        .foregroundStyle(CairnTheme.rust)
                }
                if let note = WebSearchAttribution.note(for: model.active.kind) {
                    Text(note)
                }
                Text(consentLine(for: model.active))
                    .foregroundStyle(model.willAskBeforeSearching ? CairnTheme.amber : CairnTheme.stoneLight)
            }
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        } header: {
            Text("Active provider")
        } footer: {
            Text(
                "One provider answers, the one selected here. If it fails, searching fails with the reason "
                    + "named — Cairn never sends the same words somewhere else, because a result from a "
                    + "provider you did not choose is a disclosure you cannot see."
            )
        }
    }


    // MARK: - The list

    var providerSection: some View {
        Section {
            ForEach(model.rows) { row in
                WebSearchProviderRow(model: model, row: row) {
                    editing = RowDraft(draft: WebSearchRowEdit(row: row))
                }
            }
            Button {
                editing = RowDraft(draft: WebSearchRowEdit())
            } label: {
                Label("Add a SearXNG instance", systemImage: "plus")
            }
        } header: {
            Text("Providers")
        } footer: {
            Text(
                "DuckDuckGo stays in the list whatever happens — there has to be a provider left when your "
                    + "own instance is not answering. Ollama Cloud search appears on its own while an "
                    + "Ollama Cloud server profile has a key, and disappears with that key. Only a SearXNG "
                    + "row is added, edited or deleted by hand."
            )
        }
    }

    // MARK: - How many results

    var resultsSection: some View {
        Section {
            Stepper(value: Binding(
                get: { model.resultCount },
                set: { model.setResultCount($0) }
            ), in: WebSearchSettingsModel.resultCountRange) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Results per search: \(model.resultCount)").font(.subheadline)
                    Text("The same number for whichever provider is active.")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            }
        } header: {
            Text("Results")
        } footer: {
            Text(
                "How many results Cairn puts in front of the model. It is one setting rather than one per "
                    + "provider because it is a question about this app's prompt budget: ten results on a "
                    + "small context window is an answer that has forgotten the question."
            )
        }
    }

    // MARK: - Does it work

    var testSection: some View {
        Section {
            WebSearchTestRow(model: model, row: model.active, canTest: canTest)
        } header: {
            Text("Test Connection")
        } footer: {
            Text(
                canTest
                    ? "One fixed, harmless query against the selected provider — never anything from a "
                        + "conversation, and never a query that could be traced back to what you are "
                        + "working on."
                    : "This build cannot open a connection to check a provider."
            )
        }
    }

    var footerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "A SearXNG instance you run removes the third party from the request entirely, which is why "
                    + "it is the strongest option here. A plain http address is accepted for a machine on "
                    + "your own network and refused for anything on the public internet."
            )
            if model.badgeShowsImmediately {
                Text(
                    "Web tools are on and \(model.badgeDetail), so the outbound badge is up now — before "
                        + "a search runs, not after."
                )
                .foregroundStyle(CairnTheme.rust)
            }
            if let error = model.lastError {
                Text(error).foregroundStyle(CairnTheme.rust)
            }
        }
        .font(.caption)
        .foregroundStyle(CairnTheme.stoneLight)
    }

    /// What the consent record says about a row. Three states, because the three are different facts: a
    /// grant, a refusal that will not be asked about again, and a question that has not been put yet.
    func consentLine(for row: WebSearchProviderProfile) -> String {
        switch model.consent(for: row) {
        case .granted:
            return row.reachesPublicInternet
                ? "You allowed this provider to receive searches."
                : "On your own network, so nothing is asked about it."
        case .denied:
            return "You said no to this provider. Searching stops with that answer until you change it here."
        case .undecided:
            return "Cairn will ask the first time a search is about to go to it."
        }
    }
}
