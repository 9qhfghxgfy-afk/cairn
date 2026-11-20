import Foundation

/// The copy for the Web Search screen and its provider editor.
///
/// Two rules have to survive in words as well as in code here: one provider answers and never another, and a
/// credential is a Keychain value while an ordinary header is a settings value. A popover that gets either of
/// those wrong is worse than no popover, because it teaches the wrong model of what just left the phone.
extension SettingInfoKey {
    static var webSearchProviderInfo: SettingInfo {
        SettingInfo(
            title: "Active Provider",
            detail: """
            The one provider that answers a search. If it fails, searching fails with the reason named — Cairn \
            never sends the same words to a provider you did not choose, because a result from somewhere else \
            looks exactly like a result from your own instance and you would not be able to tell. DuckDuckGo \
            stays in the list so something is always left, and only a SearXNG row is yours to add or edit.
            """
        )
    }

    static var webSearchResultCountInfo: SettingInfo {
        SettingInfo(
            title: "Result Count",
            detail: """
            How many results Cairn puts in front of the model, between 3 and 10, for whichever provider is \
            active. It is one setting rather than one per provider because it is a question about this app's \
            prompt budget: ten results on a small context window is an answer that has forgotten the question.
            """
        )
    }

    static var webSearchInstanceNameInfo: SettingInfo {
        SettingInfo(
            title: "Provider Name",
            detail: """
            The label this instance carries in the list, in the picker above, and in the Test Connection \
            button. Nothing is sent to it or derived from it — it exists so two instances on two machines are \
            tellable apart when you pick one at speed.
            """
        )
    }

    static var webSearchAddressInfo: SettingInfo {
        SettingInfo(
            title: "Base URL",
            detail: """
            Where the query goes. A machine on your own network may be reached over plain http — a LAN \
            address, the same address through your own tunnel, or a .local name — because that network is the \
            thing protecting it, and nothing beyond your own router is part of the setup. Anything on the \
            public internet must be https, and Cairn refuses it otherwise rather than badge it and carry on.
            """
        )
    }

    static var webSearchCategoriesInfo: SettingInfo {
        SettingInfo(
            title: "Categories",
            detail: """
            The SearXNG categories each search is asked for, comma-separated: general, news, images, and \
            whatever that instance has enabled. Blank asks for the instance's own default. Which categories \
            exist is the instance's decision, so a name it has not configured returns nothing rather than an \
            error.
            """
        )
    }

    static var webSearchLanguageInfo: SettingInfo {
        SettingInfo(
            title: "Language",
            detail: """
            The language code sent with each search — en, de, fr, and so on. It biases which results come \
            back; it is not a translation of your query, and Cairn does not rewrite your words. Blank leaves \
            the choice to the instance and to the language it detects.
            """
        )
    }

    static var webSearchSafeSearchInfo: SettingInfo {
        SettingInfo(
            title: "Safe Search",
            detail: """
            How strictly explicit material is filtered out of the results — Off, Moderate or Strict. The same \
            number goes to both transports Cairn speaks, so the word means one thing whichever provider \
            answers. Moderate is the default, so nothing arrives that you never asked for. The filter belongs \
            to the provider, and Off is a request rather than a guarantee.
            """
        )
    }

    static var webSearchTimeRangeInfo: SettingInfo {
        SettingInfo(
            title: "Time Range",
            detail: """
            Restricts a search to the past day, week, month or year when recency matters more than \
            relevance. Left at any time, nothing date-shaped is sent at all, so an older but better result \
            can still win. An instance you run applies the range directly; the built-in DuckDuckGo row is \
            sent that service's own equivalent parameter, and an endpoint that ignores a parameter it does \
            not know still answers, so the worst case there is a search that simply did not narrow.
            """
        )
    }

    static var webSearchTimeoutInfo: SettingInfo {
        SettingInfo(
            title: "Timeout",
            detail: """
            How long Cairn waits for this instance before the search fails as a timeout, between 5 and 60 \
            seconds. A self-hosted instance behind a tunnel is honestly slower than one on the same machine, \
            and the wait is what keeps it usable. A failure is reported with the reason named rather than \
            tried again somewhere else.
            """
        )
    }

    static var webSearchCredentialInfo: SettingInfo {
        SettingInfo(
            title: "Authorization / API Key",
            detail: """
            How this instance is authenticated: no credential, a bearer token, or a named header such as \
            X-API-Key. The value goes to the Keychain on this device only — never into the settings store, \
            never back onto this screen where a screenshot could read it. Leaving the field empty on an edit \
            keeps the stored token; the switch below it is the only way to delete one.
            """
        )
    }

    static var webSearchCustomHeadersInfo: SettingInfo {
        SettingInfo(
            title: "Custom Headers",
            detail: """
            Ordinary headers sent with every search to this instance — a proxy's routing header, say. These \
            values are stored in plain settings on the device and travel with the request, so nothing secret \
            belongs here. Cairn refuses Authorization, X-API-Key, Api-Key, Proxy-Authorization and Cookie in \
            these rows rather than keeping a secret in the clear; a credential goes in the field above.
            """
        )
    }
}
