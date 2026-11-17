import Foundation

/// Decoding for LM Studio's own REST surface, which sits beside the OpenAI-compatible endpoints
/// the same server exposes.
///
/// The v1 endpoint paths are recorded in `ServerBackend`; the JSON envelope around the model list
/// is not something this machine can verify, so the decoder accepts the envelopes LM Studio and
/// its OpenAI-compatible twin are documented to use — `{"data":[…]}`, `{"models":[…]}`, or a
/// bare array — and reads `key`, `id`, or `name` per entry. Anything else is a typed failure:
/// inventing model names would put a model on screen that the server does not have.
public enum LMStudioCodec: Sendable {
    public enum DecodeError: Error, Equatable, Sendable {
        case malformedPayload
    }

    public struct Entry: Decodable, Sendable {
        public let key: String?
        public let id: String?
        public let name: String?
        public let vision: Bool?
        public let state: String?
        public let running: Bool?

        /// The value to send back as the chat model. LM Studio's OpenAI-compatible surface keys
        /// models by `key`, so it wins over the v1 `id` when both are present.
        public var identifier: String? {
            if let key, !key.isEmpty { return key }
            if let id, !id.isEmpty { return id }
            if let name, !name.isEmpty { return name }
            return nil
        }

        public var isLoaded: Bool { running == true || state?.lowercased() == "loaded" }
    }

    private struct DataEnvelope: Decodable { let data: [Entry]? }
    private struct ModelsEnvelope: Decodable { let models: [Entry]? }

    /// The list in whatever envelope the server used, or a typed failure.
    public static func entries(in data: Data) throws -> [Entry] {
        if let bare = try? JSONDecoder().decode([Entry].self, from: data) { return bare }
        if let boxed = try? JSONDecoder().decode(DataEnvelope.self, from: data),
           let listed = boxed.data {
            return listed
        }
        if let boxed = try? JSONDecoder().decode(ModelsEnvelope.self, from: data),
           let listed = boxed.models {
            return listed
        }
        throw DecodeError.malformedPayload
    }

    /// Catalog entries. Capability flags come only from fields the server actually sent —
    /// an absent `vision` stays false rather than being assumed.
    public static func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        try entries(in: data).compactMap { entry in
            guard let id = entry.identifier else { return nil }
            return ModelInfo(
                id: id,
                displayName: entry.name ?? id,
                providerID: providerID,
                supportsVision: entry.vision == true
            )
        }
    }

    /// Ids of the models currently loaded, for the lifecycle view M3 builds. Kept separate from
    /// `decodeModels` because "installed" and "resident in memory" are different facts.
    public static func decodeLoaded(_ data: Data) throws -> [String] {
        try entries(in: data).compactMap { entry in
            entry.isLoaded ? entry.identifier : nil
        }
    }
}
