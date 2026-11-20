import Foundation

/// The copy behind one `(i)` popover: the control's own name, and what it does in plain language.
///
/// Two strings rather than one, because a card with a heading reads as an answer and a card that is only a
/// paragraph reads as a warning. A value rather than a string parameter, because the promise worth testing is
/// the one a view cannot make from the inside: that no changeable control anywhere in the app opens an empty
/// card, or a card whose explanation is the control's name said twice.
///
/// The chat's own knobs carry their copy on `SamplingKey.explainer` and `ContextKey.explainer`, which is where
/// their wire encoding lives; everything that has no wire key of its own — appearance, providers, server
/// profiles, local sharing — is named here, so the sheet, a settings screen and a test cannot disagree.
public struct SettingInfo: Sendable, Equatable {
    /// The heading inside the card: the control's name as a person reads it, never the code's name.
    public let title: String
    /// What the control does, what it costs, and what it does not do.
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}
