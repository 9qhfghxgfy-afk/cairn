import Foundation

/// Folding a server's published model detail onto a catalog entry.
///
/// A list endpoint (`/api/tags`, `/v1/models`) reports what a model **is**; only the detail endpoint
/// (`/api/show`) states what it **can do**, and it is the only source `supportsTools` may come from.
/// Merging is therefore additive in one direction: a detail that stated a capability raises the entry's
/// flag, and a detail that stated nothing leaves the entry exactly as the catalog wrote it. Nothing is
/// inferred from a model's name, size, or quantization.
public extension ModelDetail {
    func applied(to info: ModelInfo) -> ModelInfo {
        guard info.id == id else { return info }
        var merged = info
        merged.supportsVision = merged.supportsVision || supportsVision
        merged.supportsThinking = merged.supportsThinking || supportsThinking
        merged.supportsTools = merged.supportsTools || supportsTools
        if merged.parameterSize == nil { merged.parameterSize = parameterSize }
        if merged.quantization == nil { merged.quantization = quantization }
        if merged.contextLength == nil { merged.contextLength = contextLength }
        return merged
    }
}
