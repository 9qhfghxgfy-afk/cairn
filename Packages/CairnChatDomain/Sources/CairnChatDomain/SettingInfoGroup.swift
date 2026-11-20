import Foundation

/// Which screen a `(i)` control sits on.
///
/// The groups exist so a test can state the audit as a fact: every surface with a changeable control —
/// settings, the chat form, web search, server profiles, local sharing — must have at least one entry, and an
/// entry that lands in the wrong group is an entry nobody will find. A view does not read this; a test does.
public enum SettingInfoGroup: String, Sendable, Equatable, Codable, CaseIterable {
    /// Settings: appearance, theme, the new-chat baseline, statistics, the outbound acknowledgement.
    case settings
    /// One conversation's own form: persona, answer style, reasoning.
    case chat
    /// The Web Search screen and its provider editor.
    case webSearch
    /// The server profile editor.
    case server
    /// The local-sharing screen.
    case sharing
}
