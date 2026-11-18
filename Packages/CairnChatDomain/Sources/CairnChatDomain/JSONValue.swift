import Foundation

/// A JSON value that is `Sendable`, `Equatable` and `Codable`.
///
/// Tool arguments and tool schemas cross three boundaries: the pure domain, a wire codec, and a
/// `@Sendable` tool handler running on another actor. `[String: Any]` crosses none of them — it is
/// neither `Sendable` nor `Equatable`, so a parsed argument dictionary could not be handed across an
/// actor hop or asserted equal in a test. This is the smallest shape that round-trips through
/// `JSONEncoder`/`JSONDecoder` and stays comparable.
///
/// Foundation's coders are the only dependency: nothing here reaches a socket.
public enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case text(String)
    case array([JSONValue])
    case dictionary([String: JSONValue])
}

public extension JSONValue {
    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value) where value == value.rounded(): return Int(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionaryValue: [String: JSONValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// A text value read leniently: a number or a boolean typed by a model still reads as the
    /// string the tool needs, because a model that writes `{"port": 11434}` is not wrong.
    var coercedText: String? {
        switch self {
        case .text(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        default: return nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null; return }
        if let value = try? box.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? box.decode(Int.self) { self = .integer(value); return }
        if let value = try? box.decode(Double.self) { self = .number(value); return }
        if let value = try? box.decode(String.self) { self = .text(value); return }
        if let value = try? box.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? box.decode([String: JSONValue].self) { self = .dictionary(value); return }
        throw DecodingError.dataCorruptedError(
            in: box, debugDescription: "Value is not representable as JSON"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .null: try box.encodeNil()
        case .boolean(let value): try box.encode(value)
        case .integer(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .text(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .dictionary(let value): try box.encode(value)
        }
    }
}

public extension JSONValue {
    /// Parses a JSON document, or nil when it is not JSON at all — which is the normal answer for a
    /// model that emitted prose instead of a tool call, so it is not an error worth throwing.
    static func decode(from data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func decode(from text: String) -> JSONValue? {
        decode(from: Data(text.utf8))
    }

    /// Byte-stable encoding: keys sorted, so two runs over the same value produce the same bytes
    /// and a wire test can assert on the body rather than on a dictionary's mood.
    var encoded: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// Human-readable, for the tool card. Multi-line and indented, keys sorted for the same reason.
    var prettyText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }
}
