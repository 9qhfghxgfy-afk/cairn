import Foundation

/// Decoding for Ollama's read-only lifecycle endpoints: `/api/ps` and `/api/show`.
///
/// Pure, so the shapes are unit-tested against recorded payloads with no server involved. Every
/// optional stays optional: a size Ollama did not report is shown as unknown rather than as zero,
/// and a capability it did not state earns no badge.
public enum OllamaLifecycleCodec {
    private struct RunningEntry: Decodable {
        let name: String?
        let model: String?
        let size: Int64?
        let sizeVram: Int64?
        let expiresAt: String?
        let contextLength: Int?
        enum CodingKeys: String, CodingKey {
            case name, model, size
            case sizeVram = "size_vram"
            case expiresAt = "expires_at"
            case contextLength = "context_length"
        }
    }

    private struct RunningList: Decodable { let models: [RunningEntry]? }

    /// `/api/ps`. `name` is what to send back to the server; `model` is the friendlier label.
    public static func decodeRunning(_ data: Data) -> [ResidentServerModel] {
        guard let list = try? JSONDecoder().decode(RunningList.self, from: data) else { return [] }
        return (list.models ?? []).compactMap { entry in
            guard let id = entry.name ?? entry.model else { return nil }
            return ResidentServerModel(
                id: id,
                displayName: entry.model ?? id,
                serverName: id,
                memoryBytes: entry.size,
                vramBytes: entry.sizeVram,
                expiresAt: parseDate(entry.expiresAt),
                contextLength: entry.contextLength
            )
        }
    }

    private struct Details: Decodable {
        let parameterSize: String?
        let quantizationLevel: String?
        let family: String?
        enum CodingKeys: String, CodingKey {
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
            case family
        }
    }

    private struct ShowPayload: Decodable {
        let details: Details?
        let contextLength: Int?
        /// Published capability names, when this Ollama version states them. Absent means no
        /// badge — the rule that keeps a guess off the screen.
        let capabilities: [String]?
        let license: String?
        enum CodingKeys: String, CodingKey {
            case details, capabilities, license
            case contextLength = "context_length"
        }
    }

    public static func decodeDetail(_ data: Data, model: String) throws -> ModelDetail {
        guard let payload = try? JSONDecoder().decode(ShowPayload.self, from: data) else {
            throw OllamaCodec.CodecError.malformedLine
        }
        let published = Set((payload.capabilities ?? []).map { $0.lowercased() })
        return ModelDetail(
            id: model,
            parameterSize: payload.details?.parameterSize,
            quantization: payload.details?.quantizationLevel,
            contextLength: payload.contextLength,
            supportsVision: published.contains("vision"),
            supportsTools: published.contains("tools"),
            supportsThinking: published.contains("thinking"),
            publishedNote: payload.details?.family ?? payload.license
        )
    }

    /// Tolerant of both the plain and the fractional-seconds ISO-8601 forms Ollama emits.
    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
