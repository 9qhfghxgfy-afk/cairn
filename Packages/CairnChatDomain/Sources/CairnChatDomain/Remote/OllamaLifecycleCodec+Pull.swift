import Foundation

/// The `/api/pull` progress stream and the request bodies for the write-side calls, kept apart
/// from the read-side decoding so each file stays small and single-purpose.
extension OllamaLifecycleCodec {
    private struct ProgressLine: Decodable {
        let status: String?
        let completed: Int64?
        let total: Int64?
        let error: String?
        let name: String?
    }

    /// One NDJSON line of a pull. An unreadable line yields nil rather than failing a download
    /// that is otherwise going fine — a progress bar is not the authority on whether the model
    /// landed.
    public static func decodeProgressLine(_ line: String, model: String) -> ModelPullProgress? {
        guard let decoded = progressLine(in: line),
              let status = decoded.status ?? decoded.error
        else { return nil }
        return ModelPullProgress(
            modelName: decoded.name ?? model,
            statusText: status,
            completedBytes: decoded.completed,
            totalBytes: decoded.total
        )
    }

    /// Ollama reports a failed pull with HTTP 200 and an in-band `{"error": ...}` line, so the
    /// status code cannot be trusted on its own here.
    public static func inBandError(in line: String) -> String? {
        progressLine(in: line)?.error
    }

    private static func progressLine(in line: String) -> ProgressLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProgressLine.self, from: data)
    }

    // MARK: - Bodies

    /// `keep_alive: 0` is the documented way to release a loaded model without deleting it.
    public static func unloadRequestBody(model: String) throws -> Data {
        try encodedBody(["name": model, "keep_alive": 0])
    }

    public static func pullRequestBody(model: String) throws -> Data {
        try encodedBody(["name": model, "stream": true])
    }

    public static func deleteRequestBody(model: String) throws -> Data {
        try encodedBody(["name": model])
    }

    public static func showRequestBody(model: String) throws -> Data {
        try encodedBody(["name": model])
    }

    private static func encodedBody(_ payload: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload)
        else { throw OllamaCodec.CodecError.malformedLine }
        return data
    }
}
