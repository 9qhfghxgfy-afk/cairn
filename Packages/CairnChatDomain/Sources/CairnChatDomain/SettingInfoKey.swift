import Foundation

/// Every changeable control in the app that has no domain key of its own, named once.
///
/// The sampling knobs and the injected-context toggles already have one — `SamplingKey` and `ContextKey` carry
/// `explainer` beside the wire name they belong to. Everything else a person can change (the theme, the
/// new-chat baseline, a search provider, a server profile, the shared port) is named here instead, so the copy
/// is written once in a pure module where a test can reach it and is read by whichever view draws the row.
///
/// Adding a control without adding its entry here is a compile error at `info` below, which is the point: an
/// `(i)` that opens a blank card is worse than no `(i)` at all, and a view cannot notice that it happened.
public enum SettingInfoKey: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    // Settings screen.
    case appearance
    case colorTheme
    case defaultConfiguration
    case injectedContext
    case generationStats
    case webToolsOutbound
    case downloadCatalogShown
    case modelDownloadsOutbound
    case huggingFaceToken
    case ollamaRegistryToken

    // One conversation's own configuration form.
    case persona
    case answerStyle
    case askForReasoning
    case toolSwitches
    case temporaryChat

    // The Web Search screen and its provider editor.
    case webSearchProvider
    case webSearchResultCount
    case webSearchInstanceName
    case webSearchAddress
    case webSearchCategories
    case webSearchLanguage
    case webSearchSafeSearch
    case webSearchTimeRange
    case webSearchTimeout
    case webSearchCredential
    case webSearchCustomHeaders

    // The server profile editor.
    case serverName
    case serverBackend
    case serverAddress
    case serverUseEnabled
    case serverPublicOptIn
    case serverToken
    case serverCustomHeaders

    // The local-sharing screen.
    case shareOnLocalNetwork
    case sharePeerKey
    case sharePort
    case shareEngines

    public var id: String { rawValue }

    /// Which surface the control lives on, so a test can require every surface to be covered.
    public var group: SettingInfoGroup {
        switch self {
        case .appearance, .colorTheme, .defaultConfiguration, .injectedContext,
             .generationStats, .webToolsOutbound, .downloadCatalogShown, .modelDownloadsOutbound,
             .huggingFaceToken, .ollamaRegistryToken:
            return .settings
        case .persona, .answerStyle, .askForReasoning, .toolSwitches, .temporaryChat:
            return .chat
        case .webSearchProvider, .webSearchResultCount, .webSearchInstanceName, .webSearchAddress,
             .webSearchCategories, .webSearchLanguage, .webSearchSafeSearch, .webSearchTimeRange,
             .webSearchTimeout, .webSearchCredential, .webSearchCustomHeaders:
            return .webSearch
        case .serverName, .serverBackend, .serverAddress, .serverUseEnabled, .serverPublicOptIn,
             .serverToken, .serverCustomHeaders:
            return .server
        case .shareOnLocalNetwork, .sharePeerKey, .sharePort, .shareEngines:
            return .sharing
        }
    }

    /// The card's copy, from the group file this key's case is listed in.
    public var info: SettingInfo {
        switch self {
        case .appearance: return Self.appearanceInfo
        case .colorTheme: return Self.colorThemeInfo
        case .defaultConfiguration: return Self.defaultConfigurationInfo
        case .injectedContext: return Self.injectedContextInfo
        case .generationStats: return Self.generationStatsInfo
        case .webToolsOutbound: return Self.webToolsOutboundInfo
        case .downloadCatalogShown: return Self.downloadCatalogShownInfo
        case .modelDownloadsOutbound: return Self.modelDownloadsOutboundInfo
        case .huggingFaceToken: return Self.huggingFaceTokenInfo
        case .ollamaRegistryToken: return Self.ollamaRegistryTokenInfo
        case .persona: return Self.personaInfo
        case .answerStyle: return Self.answerStyleInfo
        case .askForReasoning: return Self.askForReasoningInfo
        case .toolSwitches: return Self.toolSwitchesInfo
        case .temporaryChat: return Self.temporaryChatInfo
        case .webSearchProvider: return Self.webSearchProviderInfo
        case .webSearchResultCount: return Self.webSearchResultCountInfo
        case .webSearchInstanceName: return Self.webSearchInstanceNameInfo
        case .webSearchAddress: return Self.webSearchAddressInfo
        case .webSearchCategories: return Self.webSearchCategoriesInfo
        case .webSearchLanguage: return Self.webSearchLanguageInfo
        case .webSearchSafeSearch: return Self.webSearchSafeSearchInfo
        case .webSearchTimeRange: return Self.webSearchTimeRangeInfo
        case .webSearchTimeout: return Self.webSearchTimeoutInfo
        case .webSearchCredential: return Self.webSearchCredentialInfo
        case .webSearchCustomHeaders: return Self.webSearchCustomHeadersInfo
        case .serverName: return Self.serverNameInfo
        case .serverBackend: return Self.serverBackendInfo
        case .serverAddress: return Self.serverAddressInfo
        case .serverUseEnabled: return Self.serverUseEnabledInfo
        case .serverPublicOptIn: return Self.serverPublicOptInInfo
        case .serverToken: return Self.serverTokenInfo
        case .serverCustomHeaders: return Self.serverCustomHeadersInfo
        case .shareOnLocalNetwork: return Self.shareOnLocalNetworkInfo
        case .sharePeerKey: return Self.sharePeerKeyInfo
        case .sharePort: return Self.sharePortInfo
        case .shareEngines: return Self.shareEnginesInfo
        }
    }
}
