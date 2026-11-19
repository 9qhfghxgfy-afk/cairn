import Foundation

/// A tool-switch blob written by an older build still has to decode.
///
/// Synthesised `Codable` reads every property with `decode`, so a blob written before `get_location`
/// existed would fail on the missing key — and a failed `ToolToggleSet` decode takes the whole chat
/// configuration down with it, which is how adding one switch would have quietly reset a person's web
/// switches and their chip. Every key is therefore read with `decodeIfPresent`, and a missing key means
/// "this chat predates the switch", answered with the value a new chat would have had.
///
/// `isEnabled` falls back to **off** for the same reason `ChatConfig` does: a migration may not arm a
/// conversation nobody armed.
extension ToolToggleSet {
    private enum Keys: String, CodingKey {
        case isEnabled, webSearch, webFetch, wikiSearch, calculator, composeMail, getLocation
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        isEnabled = try box.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        webSearch = try box.decodeIfPresent(Bool.self, forKey: .webSearch) ?? true
        webFetch = try box.decodeIfPresent(Bool.self, forKey: .webFetch) ?? true
        wikiSearch = try box.decodeIfPresent(Bool.self, forKey: .wikiSearch) ?? true
        calculator = try box.decodeIfPresent(Bool.self, forKey: .calculator) ?? true
        composeMail = try box.decodeIfPresent(Bool.self, forKey: .composeMail) ?? true
        getLocation = try box.decodeIfPresent(Bool.self, forKey: .getLocation) ?? true
    }
}
