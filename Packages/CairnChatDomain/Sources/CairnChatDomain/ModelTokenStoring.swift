import Foundation

/// The two optional account tokens Cairn can hold, named once.
///
/// Both are optional in the strongest sense: every public model in Cairn's library downloads without
/// either one, and nothing in the app asks for a token before it will show a screen. A token is what
/// changes an answer from "this repository asks you to accept its terms first" into the bytes.
///
/// The raw value is the storage key's stable half, so renaming a case's display name cannot silently
/// strand a token the person already saved.
public enum ModelTokenKind: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    /// Hugging Face Hub: gated repositories and a higher request ceiling against the same public host.
    case huggingFace
    /// An Ollama endpoint that asks for a registry credential — a hosted registry or a proxy in front
    /// of one. A server on the user's own network needs neither.
    case ollamaRegistry

    public var id: String { rawValue }

    /// The name on the row.
    public var label: String {
        switch self {
        case .huggingFace: return "Hugging Face Token"
        case .ollamaRegistry: return "Ollama Token"
        }
    }

    /// The short line under the row: what a token buys, and what it does not.
    public var caption: String {
        switch self {
        case .huggingFace:
            return "Public models need no token. A token reaches repositories that ask first."
        case .ollamaRegistry:
            return "Only for a registry that asks. A server on your own network needs none."
        }
    }

    /// The glyph on the row and on the sheet's button.
    public var iconName: String {
        switch self {
        case .huggingFace: return "key.fill"
        case .ollamaRegistry: return "person.crop.circle"
        }
    }

    /// The Keychain account name, fixed so a rename of `label` cannot lose a saved token.
    public var storageAccount: String {
        switch self {
        case .huggingFace: return "hugging-face"
        case .ollamaRegistry: return "ollama-registry"
        }
    }

    /// The `(i)` card's key, so the explanation is written once in the domain and a test can read it.
    public var infoKey: SettingInfoKey {
        switch self {
        case .huggingFace: return .huggingFaceToken
        case .ollamaRegistry: return .ollamaRegistryToken
        }
    }

    /// Which library this credential belongs to, for the sheet that offers it beside a download.
    public var appliesToPhoneLibrary: Bool { self == .huggingFace }
}

/// Optional tokens, kept in the device's own secure storage.
///
/// The store is a boundary rather than a field because only the App layer has a Keychain: `CairnAppUI`
/// may not open one and the domain may not know one exists. What the view model gets back is a yes-or-no,
/// never the value — a token that reaches a view can reach a label, and a label can reach a screenshot,
/// a share sheet, or a log line.
///
/// Nothing here is ever written to SwiftData or to Settings. A token is a credential for a third-party
/// account, and the rules for those in this app are the rules for a server's own token: Keychain,
/// device-only, and never in a plist, a log, or an exported file.
///
/// `Sendable` rather than `@MainActor`, because the value is needed off the main actor: a model download
/// builds its request on the task carrying the transfer, and routing that question through the main actor
/// would put the screen in the middle of a byte transfer for no reason. The real store is a struct over
/// the Keychain API, which is thread-safe and synchronous.
public protocol ModelTokenStoring: Sendable {
    /// The token, or nil when none is saved. Read by the code that builds a request, not by a view.
    func token(for kind: ModelTokenKind) -> String?
    /// Save, replacing whatever was there. An empty or whitespace-only value removes instead, because a
    /// person who clears the field and presses Save means "take it off this phone".
    /// Returns false when the write failed, so the screen can say so rather than showing a saved state
    /// that does not exist.
    @discardableResult
    func save(_ token: String, for kind: ModelTokenKind) -> Bool
    @discardableResult
    func remove(_ kind: ModelTokenKind) -> Bool
}