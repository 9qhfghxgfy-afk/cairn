import Foundation

/// Cairn's curated download library, as rows.
///
/// Static on purpose. A library screen must open with no network and must not make a request the
/// person did not ask for; only an actual download reaches Hugging Face or a server, and that path
/// carries the outbound opt-in and the badge.
///
/// Two lists, because they name two different things. `onDevice` holds MLX repositories this phone
/// can hold, addressed by their exact Hugging Face repository id. `ollama` holds tags an Ollama
/// server installs, addressed by the exact tag. The Download tab shows one of them depending on
/// which engine it is pointed at, and says which.
///
/// The metadata rule: every field is copied from a published fact. `downloadBytes` is the
/// publisher's stated size; `capabilityLabels` are the words the publisher uses for what it states,
/// never a guess from a name or a size; `sortOrder` is Cairn's rank, not a download counter nobody
/// fetched. The summaries are Cairn's own words.
public enum ModelCatalog {
    /// The curated on-device MLX library, in Cairn's rank.
    public static var onDevice: [LocalCatalogRow] { onDeviceRows }

    /// The curated Ollama library tags, in Cairn's rank.
    public static var ollama: [LocalCatalogRow] { ollamaRows }

    /// The list a destination installs from, with nothing claimed as installed.
    public static func rows(for origin: ModelCatalogOrigin) -> [LocalCatalogRow] {
        switch origin {
        case .onDevice: return onDeviceRows
        case .ollamaLibrary: return ollamaRows
        case .custom: return []
        }
    }

    /// Marks a curated list against what the destination reports holding, leaving order and metadata
    /// untouched. An id the destination does not list reads as not installed rather than as it was
    /// guessed, which is what stops a card offering a download for a model already on the disk.
    public static func marking(
        _ entries: [LocalCatalogRow],
        installed installedIDs: Set<String>
    ) -> [LocalCatalogRow] {
        entries.map { $0.marking(installed: installedIDs.contains($0.id)) }
    }

    /// Midnight UTC, so the order is reproducible in a test.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
