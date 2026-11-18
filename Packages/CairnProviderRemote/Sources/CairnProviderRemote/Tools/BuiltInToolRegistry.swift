import Foundation
import CairnChatDomain

/// The tools this build can offer, assembled in one place.
///
/// Two of the five need nothing beyond the phone and are always present: the calculator, and the mail
/// draft, which only ever opens a composer on this screen. The three web tools are added **only when
/// the outbound acknowledgement is up**, because a tool a model can be told about but not run is worse
/// than no tool at all — a model that believes it searched will report a result it never got. The chat's
/// own `Tools` chip and the per-tool switches then decide what a given turn actually sees.
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
    public static func make(
        searchState: @escaping WebSearchStateReader,
        mailPresenter: (any MailDraftPresenting)? = nil,
        webToolsAllowed: Bool,
        transport: any WebRequesting = WebHTTPTransport()
    ) -> ToolRegistry {
        var tools: [any ToolExecuting] = [CalculatorTool()]
        if let mailPresenter {
            tools.append(ComposeMailTool(presenter: mailPresenter))
        }
        guard webToolsAllowed else { return ToolRegistry(tools: tools) }
        tools.append(WebSearchTool(state: searchState, transport: transport))
        tools.append(WebFetchTool(transport: transport))
        tools.append(WikiSearchTool(transport: transport))
        return ToolRegistry(tools: tools)
    }

    /// The five names, in the order the settings screen lists them — read back from the domain so a
    /// renamed tool cannot survive in one list and silently disappear from another.
    public static var names: [String] { BuiltInTool.allNames }
}
