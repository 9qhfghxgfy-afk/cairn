import SwiftUI
import CairnChatDomain

/// Add or edit one SearXNG row.
///
/// The address is live-typed but validated by the domain on save, with the domain's own sentence shown
/// where it failed — a field that guessed at validity in advance would disagree with the store at least once
/// a week. Plain `http` is accepted for a private address and refused for a public host, and the reason is
/// said rather than the field simply refusing to accept the characters.
///
/// The credential section is the part to read twice. The token field writes to the Keychain and nothing else:
/// it is never read back to be displayed, never written to the settings store, and never sent anywhere except
/// under the one header shape chosen here. Leaving the field untouched on an edit means "keep the stored
/// token", which is why it starts empty rather than showing dots.
@MainActor
struct WebSearchProviderEditor: View {
    /// A header row as typed. Ordinary headers only — a credential-named one is refused on save with the
    /// reason, not stripped in silence.
    struct HeaderRow: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
    }

    /// Which of the three credential shapes the row is being set to.
    enum CredentialChoice: Hashable, CaseIterable {
        case none, bearer, namedHeader

        var label: String {
            switch self {
            case .none: return "No credential"
            case .bearer: return "Bearer token"
            case .namedHeader: return "Named header"
            }
        }
    }

    let model: WebSearchSettingsModel
    let draft: WebSearchRowEdit
    /// Not `private`: `save()` closes this sheet from `WebSearchProviderEditor+Sections`, a different
    /// file, and a `private` property is visible only in the file that declares it.
    @Environment(\.dismiss) var dismiss

    @State var name: String
    @State var address: String
    @State var categories: String
    @State var language: String
    @State var safeSearch: WebSearchSafeSearch
    /// nil means no date filter: the provider decides how far back a search reaches.
    @State var timeRange: WebSearchTimeRange?
    @State var timeoutSeconds: Int
    @State var choice: CredentialChoice
    @State var secretHeaderName: String
    /// Empty and untouched means "leave the stored token alone". Anything typed means "this is it now", and
    /// the remove switch is the third state — a switch rather than clearing the field, so that deleting a
    /// credential cannot happen by accident while editing a name. The field never starts populated, which is
    /// what makes "empty" mean two different things and why the switch has to say which one is meant.
    @State var token: String
    @State var removingStored = false
    @State var headerRows: [HeaderRow]

    init(model: WebSearchSettingsModel, draft: WebSearchRowEdit) {
        self.model = model
        self.draft = draft
        _name = State(initialValue: draft.name)
        _address = State(initialValue: draft.address)
        _categories = State(initialValue: draft.categories.joined(separator: ", "))
        _language = State(initialValue: draft.language)
        _safeSearch = State(initialValue: draft.safeSearch)
        _timeRange = State(initialValue: draft.timeRange)
        _timeoutSeconds = State(initialValue: draft.timeoutSeconds)
        _choice = State(initialValue: Self.choice(for: draft.credentialShape))
        _secretHeaderName = State(initialValue: {
            if case .secretHeader(let header) = draft.credentialShape { return header }
            return "X-API-Key"
        }())
        _token = State(initialValue: "")
        _headerRows = State(initialValue: draft.customHeaders
            .sorted { $0.key < $1.key }
            .map { HeaderRow(name: $0.key, value: $0.value) })
    }

    var body: some View {
        Form {
            basicsSection
            credentialSection
            headerSection
        }
        .navigationTitle(draft.id == nil ? "Add SearXNG" : "Edit provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

}


