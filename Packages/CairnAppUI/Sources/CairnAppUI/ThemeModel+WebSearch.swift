import Foundation
import CairnChatDomain

/// The web-search half of the app-wide settings: the legacy SearXNG address, the provider list, the
/// chosen provider, the result count, the per-provider consent answers and the page-read answer.
///
/// Split from the settings object's own file because these are one subject — the web surface — and the
/// file had grown to carry two. They still go through the same `mutate` as every other row, so a provider
/// list can never be saved without the consent record that belongs to it.
extension ThemeModel {
    /// The user's own SearXNG endpoint; nil or empty means "not set", which is what makes the keyless
    /// default the answer instead of a broken address.
    ///
    /// **Legacy**, kept while the import that turns it into a provider row still has to run on installs that
    /// predate providers. New code writes `setWebSearch`.
    public func setSearXNGURL(_ url: String?) {
        mutate { $0.setSearXNGURL(url) }
    }

    /// The whole web-search settings value, written as one unit.
    ///
    /// Providers, selection, result count and consent travel together because a provider list saved without
    /// its consent record would be a list that can search somewhere the user never agreed to.
    public func setWebSearch(_ search: WebSearchSettings) {
        mutate { $0.setWebSearch(search) }
    }

    /// Selecting a provider, and clearing the notice that says selection moved. Both go through the store so
    /// a row the user tapped cannot be ignored, and a notice cannot outlive the choice it describes.
    public func selectWebSearchProvider(id: UUID) {
        mutate { $0.selectWebSearchProvider(id: id) }
    }

    public func setWebSearchResultCount(_ count: Int) {
        mutate { $0.setWebSearchResultCount(count) }
    }

    /// The per-provider answer to the outbound question: granted, or declined and remembered.
    public func grantWebSearchConsent(for profile: WebSearchProviderProfile) {
        mutate { $0.grantWebSearchConsent(for: profile) }
    }

    public func denyWebSearchConsent(for profile: WebSearchProviderProfile) {
        mutate { $0.denyWebSearchConsent(for: profile) }
    }

    /// Whether a page may be read off this device, as one answer for the whole tool. nil means the question
    /// has never been put — which is not permission, and is why the first read asks.
    public func setWebFetchAllowed(_ allowed: Bool?) {
        mutate { $0.setWebFetchAllowed(allowed) }
    }
}
