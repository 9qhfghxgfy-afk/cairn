import Foundation
import CairnChatDomain

/// The tools this build can offer, assembled in one place.
///
/// The tools that need nothing beyond the phone are always present: the calculator, and the mail draft,
/// which only ever opens a composer on this screen. `get_location` joins when this build has a position
/// source, because it too sends nothing anywhere — what gates it is the user's consent, which the tool
/// asks for itself. The three web tools are added **only when the outbound acknowledgement is up**,
/// because a tool a model can be told about but not run is worse than no tool at all — a model that
/// believes it searched will report a result it never got. The chat's own `Tools` chip and the per-tool
/// switches then decide what a given turn actually sees.
public enum BuiltInToolRegistry {
    /// Builds the registry.
    ///
    /// - Parameters:
    ///   - searchState: reads Settings, the active server and its Keychain-backed key at the moment a
    ///     search runs, so the route is chosen from what is true now rather than from a snapshot taken
    ///     at launch.
    ///   - mailPresenter: the device's mail composer; nil on a build or device with none, which leaves
    ///     `compose_mail` out rather than offering a tool that can only fail.
    ///   - webToolsAllowed: the app-wide acknowledgement that a tool's query may reach a public service.
    ///   - consent: asks a person whether the active provider may receive a query. nil means nobody is
    ///     there to ask, which is denial rather than permission — see `WebSearchConsentGate`.
    ///   - fetchConsent: the same question for `web_fetch`, so one decision covers both ways a web tool can
    ///     leave the device. nil is the same denial. A page read is not a query to the selected provider, so
    ///     it is asked about by host rather than by provider — but it is the same person's answer.
    ///   - locationTool: `get_location`, built at the app layer, which is the only place a `CLLocationManager`
    ///     and the consent sheet in front of it both exist. nil on a build with no position source leaves the
    ///     tool out of the registry entirely, exactly as a device with no mail composer gets no
    ///     `compose_mail` — a tool that can only ever answer "no" is worse to a model than no tool.
    public static func make(
        searchState: @escaping WebSearchStateReader,
        mailPresenter: (any MailDraftPresenting)? = nil,
        webToolsAllowed: Bool,
        transport: any WebRequesting = WebHTTPTransport(),
        consent: WebSearchConsentRequester? = nil,
        fetchConsent: WebFetchConsentRequester? = nil,
        locationTool: (any ToolExecuting)? = nil
    ) -> ToolRegistry {
        var tools: [any ToolExecuting] = [CalculatorTool()]
        if let mailPresenter {
            tools.append(ComposeMailTool(presenter: mailPresenter))
        }
        // Offered with the outbound badge down, because a position read is not a request to anybody: no
        // reverse geocoding, no endpoint. What gates it is the user's own consent, asked by the tool.
        if let locationTool {
            tools.append(locationTool)
        }
        guard webToolsAllowed else { return ToolRegistry(tools: tools) }
        tools.append(WebSearchTool(state: searchState, transport: transport, consent: consent))
        tools.append(WebFetchTool(transport: transport, consent: fetchConsent))
        tools.append(WikiSearchTool(transport: transport))
        return ToolRegistry(tools: tools)
    }

    /// The six names, in the order the settings screen lists them — read back from the domain so a
    /// renamed tool cannot survive in one list and silently disappear from another.
    public static var names: [String] { BuiltInTool.allNames }
}
