import Foundation

/// A sampling value in the shape the wire wants. Ollama distinguishes an integer option from a
/// float option, and `40` and `40.0` are not the same JSON, so the distinction is carried rather
/// than inferred at encode time.
public enum SamplingValue: Sendable, Equatable {
    case double(Double)
    case int(Int)

    public var doubleValue: Double {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        }
    }

    public var intValue: Int {
        switch self {
        case .double(let value): return Int(value)
        case .int(let value): return value
        }
    }
}

extension SamplingValue: Encodable {
    /// Encodes as a bare JSON number. This type exists only for the outbound request body — a chat
    /// configuration persists its knobs as plain Swift optionals — so there is no second, tagged
    /// encoding to reconcile with, and `{"temperature": 0.8}` is the only shape that is correct.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}
