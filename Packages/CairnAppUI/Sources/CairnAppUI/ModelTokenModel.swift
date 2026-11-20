import Foundation
import CairnChatDomain

/// The view model behind the optional token rows: a yes-or-no per kind, and nothing else.
///
/// It never hands a token to a view. `isSaved` is the whole interface a screen gets, because a value that
/// reaches a view can reach a label, and a label can reach a screenshot, a share sheet, or a log line. The
/// value itself travels only between the store and the code that builds one request.
///
/// The drafts are deliberately not remembered. A token typed into a field is a secret sitting in this
/// process's memory; keeping it there after a save would mean a re-render or a re-open of the screen could
/// redraw it, and the screen has no reason to show a person something they can never read back.
@MainActor
public final class ModelTokenModel: ObservableObject {
    /// What each kind answered the last time it was asked. This is the remembered *fact* — "there is a
    /// token here" — never the token.
    @Published private var savedKinds: Set<ModelTokenKind> = []
    /// The latest thing typed into a field, held until the row is left. Cleared on save and on remove.
    @Published private var drafts: [ModelTokenKind: String] = [:]
    /// Why an action did not work, in words, when it did not. A token that silently fails to save is the
    /// worst possible outcome: the next download fails with a 401 and nothing here says why.
    @Published public var notice: String?

    private let store: (any ModelTokenStoring)?

    /// Seeds the answer from the store so a row never asks the Keychain while a screen is being drawn.
    ///
    /// A token read is a blocking call into the system's secure storage, and this row re-renders on every
    /// keystroke — a question asked during `body` would be asked four times per pass, on the main thread, for
    /// a value the row is not even allowed to display. So the yes-or-no is computed once here and kept in a
    /// set, and the store is consulted again only when this model writes.
    public init(store: (any ModelTokenStoring)? = nil) {
        self.store = store
        if let store {
            savedKinds = Set(ModelTokenKind.allCases.filter { store.token(for: $0) != nil })
        }
    }

    /// Whether this kind has a token on this phone. Reads the set, not the store: see the note on `init`.
    public func isSaved(for kind: ModelTokenKind) -> Bool {
        savedKinds.contains(kind)
    }

    /// What was typed here and not yet saved. A row re-created by a list refresh should not come back empty
    /// while a person is mid-word, but it should also never come back with a token.
    public func draft(for kind: ModelTokenKind) -> String {
        drafts[kind, default: ""]
    }

    public func setDraft(_ text: String, for kind: ModelTokenKind) {
        drafts[kind] = text
    }

    /// Saves what the field holds, and says so out loud when the phone refused the write. A row that shows a
    /// saved state after a failed write is worse than a row that admits it — the next download would answer
    /// 401 and nothing on this screen would explain why.
    ///
    /// An empty value removes rather than storing an empty string, which is what the store does too: a saved
    /// empty token would claim a credential that cannot authenticate anything.
    public func save(_ text: String, for kind: ModelTokenKind) {
        guard let store else {
            notice = "There is no secure storage here, so nothing was saved."
            return
        }
        let written = store.save(text, for: kind)
        drafts[kind] = ""
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if written {
            if value.isEmpty { savedKinds.remove(kind) } else { savedKinds.insert(kind) }
            notice = nil
        } else {
            notice = "This phone would not accept the \(kind.label.lowercased()). Nothing was saved."
        }
    }

    /// Takes the token off this phone, and admits it when the phone kept it anyway.
    public func remove(for kind: ModelTokenKind) {
        guard let store else {
            notice = "There is no storage here to take a token out of."
            return
        }
        let gone = store.remove(kind)
        drafts[kind] = ""
        if gone { savedKinds.remove(kind) }
        notice = gone ? nil : "This phone still holds a token for \(kind.label)."
    }

    /// Clears the notice, so a stale complaint cannot sit above a row that has since been fixed.
    public func clearNotice() {
        notice = nil
    }
}
