import Foundation

extension OpenAICodec {
    // MARK: - Metrics + catalog

    /// Metrics from real usage only; if the server never reported token
    /// counts, metrics stay nil (measured, never estimated).
    public static func metrics(
        promptTokens: Int?,
        completionTokens: Int?,
        elapsedSeconds: Double,
        timeToFirstTokenSeconds: Double?,
        finishReason: FinishReason
    ) -> GenerationMetrics? {
        guard let tokens = completionTokens, tokens > 0 else { return nil }
        return GenerationMetrics(
            tokensGenerated: tokens,
            promptTokens: promptTokens,
            elapsedSeconds: elapsedSeconds,
            timeToFirstTokenSeconds: timeToFirstTokenSeconds,
            finishReason: finishReason
        )
    }

    struct WireModel: Decodable { let id: String }
    struct WireModelList: Decodable { let data: [WireModel]? }

    /// Decodes `/v1/models` (`{"data":[{"id":…}]}`). Capability metadata is not
    /// invented: an OpenAI-compatible listing carries no thinking/vision flags.
    public static func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        let list: WireModelList
        do {
            list = try JSONDecoder().decode(WireModelList.self, from: data)
        } catch {
            throw CodecError.malformedPayload
        }
        return (list.data ?? []).map { model in
            ModelInfo(id: model.id, displayName: model.id, providerID: providerID)
        }
    }
}
