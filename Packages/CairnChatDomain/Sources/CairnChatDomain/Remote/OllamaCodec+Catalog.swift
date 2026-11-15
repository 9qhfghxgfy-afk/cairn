import Foundation

extension OllamaCodec {
    // MARK: - Catalog decoding

    struct WireDetails: Decodable {
        let parameterSize: String?
        let quantizationLevel: String?
        let contextLength: Int?
        let projector: String?
        let supportsThinking: Bool?
        enum CodingKeys: String, CodingKey {
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
            case contextLength = "context_length"
            case projector
            case supportsThinking = "supports_thinking"
        }
    }

    struct WireModel: Decodable {
        let name: String
        let details: WireDetails?
    }

    struct WireModelList: Decodable {
        let models: [WireModel]?
    }

    /// Decodes `/api/tags` or `/api/ps` payloads (`{"models":[…]}`).
    /// Vision = the model carries a multimodal projector; thinking = the
    /// server metadata explicitly says so. Absent metadata stays `false`.
    public static func decodeModelList(_ data: Data, providerID: String) throws -> [ModelInfo] {
        let list: WireModelList
        do {
            list = try JSONDecoder().decode(WireModelList.self, from: data)
        } catch {
            throw CodecError.malformedLine
        }
        return (list.models ?? []).map { model in
            let details = model.details
            let hasProjector = (details?.projector?.isEmpty == false)
            return ModelInfo(
                id: model.name,
                displayName: model.name,
                providerID: providerID,
                parameterSize: details?.parameterSize,
                quantization: details?.quantizationLevel,
                contextLength: details?.contextLength,
                supportsVision: hasProjector,
                supportsThinking: details?.supportsThinking ?? false
            )
        }
    }

    struct WireVersion: Decodable { let version: String? }

    public static func decodeVersion(_ data: Data) throws -> String? {
        do {
            return try JSONDecoder().decode(WireVersion.self, from: data).version
        } catch {
            throw CodecError.malformedLine
        }
    }

    /// Body for `/api/pull` and `/api/delete`.
    public static func nameRequestBody(model: String, stream: Bool? = nil) throws -> Data {
        struct Body: Encodable { let name: String; let stream: Bool? }
        return try JSONEncoder().encode(Body(name: model, stream: stream))
    }
}
