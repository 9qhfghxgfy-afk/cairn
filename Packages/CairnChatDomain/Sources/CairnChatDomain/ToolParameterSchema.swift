import Foundation

/// One property inside a tool's parameter schema.
///
/// Cairn authors every tool it ships, so this only ever *encodes* — there is no decoder, and no
/// third-party schema is ever trusted enough to be executed against. The kinds are the JSON Schema
/// subset both documented dialects accept (Ollama `tools`, OpenAI `tools`).
public struct ToolParameter: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case string
        case integer
        case number
        case boolean
        case stringArray
    }

    public var kind: Kind
    public var description: String

    public init(kind: Kind, description: String = "") {
        self.kind = kind
        self.description = description
    }
}

extension ToolParameter: Encodable {
    private enum CodingKeys: String, CodingKey { case type, description, items }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .stringArray:
            // `array` needs its `items` or a strict server rejects the whole tool definition.
            try box.encode("array", forKey: .type)
            try box.encode(["type": "string"], forKey: .items)
        default:
            try box.encode(kind.rawValue, forKey: .type)
        }
        // An empty description encodes as `""`, which reads to a model as "this field means nothing".
        if !description.isEmpty { try box.encode(description, forKey: .description) }
    }
}

/// A tool's `parameters` block: a JSON Schema object, narrowed to what a Cairn tool can ask for.
public struct ToolParameterSchema: Sendable, Equatable {
    public var properties: [String: ToolParameter]
    public var required: [String]

    public init(properties: [String: ToolParameter], required: [String] = []) {
        self.properties = properties
        // Sorted, so the required list is byte-stable across runs and a wire test can assert on it.
        self.required = required.sorted()
    }

    /// A tool that takes nothing. Sent as an empty object, not as a missing key: a schema that is
    /// absent makes some servers refuse the tool outright.
    public static let none = ToolParameterSchema(properties: [:])

    public var isEmpty: Bool { properties.isEmpty }

    /// True when every `required` name is also a declared property — a schema that names a property
    /// it never describes is a bug in Cairn, not a choice the model can recover from.
    public var isConsistent: Bool {
        required.allSatisfy { properties[$0] != nil }
    }

    public func value(_ name: String, in arguments: [String: JSONValue]) -> JSONValue? {
        arguments[name]
    }

    /// The missing required names, in the schema's own order. A typed error the model can act on.
    public func missingRequired(in arguments: [String: JSONValue]) -> [String] {
        required.filter { arguments[$0] == nil || arguments[$0]?.isNull == true }
    }
}

extension ToolParameterSchema: Encodable {
    private enum CodingKeys: String, CodingKey { case type, properties, required }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode("object", forKey: .type)
        try box.encode(properties, forKey: .properties)
        // Omit rather than send `[]`: an empty required array is legal but several servers treat a
        // present-but-empty list differently from an absent one.
        if !required.isEmpty { try box.encode(required, forKey: .required) }
    }

    /// Byte-stable JSON for the wire. Sorted keys, because a request body that shuffles between two
    /// identical turns makes a wire test meaningless.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
