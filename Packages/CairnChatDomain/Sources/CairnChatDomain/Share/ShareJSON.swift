import Foundation

/// One JSON encoder path for every body this surface writes.
///
/// `Encodable` rather than string interpolation everywhere, because the strings in these bodies
/// are model output and user text: a quote, a newline or a backslash inside an answer must not be
/// able to end the object it sits inside. A fallback is returned rather than a throw, since a
/// server that cannot build a body still has to answer on a socket it has already opened.
enum ShareJSON {
    static func encode<T: Encodable>(_ value: T, fallback: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return text
    }
}

/// Error bodies in each dialect's own shape.
enum ShareErrorBody {
    struct OllamaError: Encodable { let error: String }
    struct OpenAIError: Encodable {
        struct Inner: Encodable {
            let message: String
            let type: String
        }
        let error: Inner
    }

    static func ollama(_ message: String) -> String {
        ShareJSON.encode(OllamaError(error: message), fallback: "{\"error\":\"request refused\"}")
    }

    static func openAI(_ message: String, kind: String) -> String {
        ShareJSON.encode(
            OpenAIError(error: OpenAIError.Inner(message: message, type: kind)),
            fallback: "{\"error\":{}}"
        )
    }
}

/// The two timestamp spellings the two dialects use, both derived from one `Date` so a stream's
/// frames and its final frame agree on when the turn happened.
public enum ShareTimestamp {
    /// Ollama's `created_at`: an ISO-8601 instant with no fractional part.
    public static func ollama(_ date: Date = Date()) -> String { date.formatted(.iso8601) }
    /// OpenAI's `created`: epoch seconds.
    public static func openAI(_ date: Date = Date()) -> Int { Int(date.timeIntervalSince1970) }
}
