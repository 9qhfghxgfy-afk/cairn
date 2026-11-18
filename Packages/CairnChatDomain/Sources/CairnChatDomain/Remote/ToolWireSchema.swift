import Foundation

/// One entry of a request's `tools` array: the shape both documented dialects publish,
/// `{"type":"function","function":{"name":…,"description":…,"parameters":{…}}}`.
///
/// Cairn authors every tool it ships, so this only ever encodes — no third-party schema is read back
/// into a call. `blurb` lands on the wire as `description` here and nowhere else, so the one
/// model-facing sentence per tool stays in the tool's own definition.
public struct WireToolSchema: Encodable, Sendable {
    public struct Function: Encodable, Sendable {
        public var name: String
        public var description: String
        public var parameters: ToolParameterSchema
    }

    public var type: String
    public var function: Function

    public init(_ definition: ToolDefinition) {
        self.type = "function"
        self.function = Function(
            name: definition.name,
            description: definition.blurb,
            parameters: definition.parameters
        )
    }

    public static func schemas(_ definitions: [ToolDefinition]) -> [WireToolSchema] {
        definitions.map(WireToolSchema.init)
    }
}

/// The arguments of a call a model asked for, held as the raw JSON blob the backend emitted and
/// re-rendered byte-stably for a dialect that wants an object rather than a string.
///
/// An undecodable blob becomes `{}` rather than an error: one malformed call is a call Cairn declines
/// and tells the model about, not a turn that dies on the way back to the server.
public enum WireToolArguments {
    public static func text(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : raw
    }

    /// A wire `arguments` value read back: an object is re-encoded as compact JSON, a string is taken
    /// as already-encoded JSON, and anything else means "no arguments". Both spellings appear across
    /// published backends, and the domain parses the text later — so neither spelling is a failure
    /// here, and a malformed blob is one declined call rather than an ended turn.
    public static func wireText(_ value: JSONValue?) -> String {
        guard let value else { return "{}" }
        if case .text(let raw) = value { return text(raw) }
        guard let data = value.encoded,
              let rendered = String(data: data, encoding: .utf8)
        else { return "{}" }
        return rendered
    }

    public static func object(_ raw: String) -> JSONValue {
        JSONValue.decode(from: text(raw)) ?? .dictionary([:])
    }
}
