import Foundation

/// What one tool looks like to a model: a name, a description, and a parameter schema.
///
/// The network class is part of the definition, not of the handler, because the privacy decision
/// ("this one leaves the device") has to be readable **before** anything is executed. A registry can
/// therefore refuse a web tool on a chat that never opted in, without ever constructing a request.
public struct ToolDefinition: Sendable, Equatable, Identifiable {
    public var name: String
    /// The text the model reads. Named `blurb` rather than `description` so a `CustomStringConvertible`
    /// on this struct can never be confused with the wire field.
    public var blurb: String
    public var parameters: ToolParameterSchema
    public var networkClass: NetworkClass

    public init(
        name: String,
        blurb: String,
        parameters: ToolParameterSchema = .none,
        networkClass: NetworkClass = .onDevice
    ) {
        self.name = name
        self.blurb = blurb
        self.parameters = parameters
        self.networkClass = networkClass
    }

    public var id: String { name }

    public var requiresNetwork: Bool { networkClass.leavesTheDevice }
    public var requiresPublicInternet: Bool { networkClass == .publicInternet }

    /// True when the schema describes itself coherently — the check a registry runs at registration
    /// so a malformed tool never reaches a model, where the only symptom would be a confusing call.
    public var isWellFormed: Bool {
        !name.isEmpty && name.count <= 64 && parameters.isConsistent
    }
}

/// The six built-in tool names, in one place.
///
/// Every comparison, badge and test in P3 goes through these constants; a literal typed in two files
/// is how a renamed tool silently stops working in one of them.
public enum BuiltInTool {
    public static let webSearch = "web_search"
    public static let webFetch = "web_fetch"
    public static let wikiSearch = "wiki_search"
    public static let calculator = "calculator"
    public static let composeMail = "compose_mail"
    public static let getLocation = "get_location"

    /// Every built-in name, in the order the UI lists them.
    public static let allNames: [String] = [
        webSearch, webFetch, wikiSearch, calculator, composeMail, getLocation,
    ]

    /// The three that reach the public internet, and so the three the `Tools` chip gates.
    public static let webNames: [String] = [webSearch, webFetch, wikiSearch]

    /// The three that need nothing beyond this device. `get_location` reads a radio, not a socket: no
    /// reverse geocoding, no request to anybody, so it belongs here with the arithmetic.
    public static let localNames: [String] = [calculator, composeMail, getLocation]

    public static func isWebTool(_ name: String) -> Bool { webNames.contains(name) }
    public static func isKnown(_ name: String) -> Bool { allNames.contains(name) }
}
