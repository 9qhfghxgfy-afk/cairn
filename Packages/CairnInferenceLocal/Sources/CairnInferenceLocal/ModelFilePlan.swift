import Foundation

/// One file the publisher lists, as far as Cairn cares.
public struct ModelFileListing: Sendable, Equatable {
    public var name: String
    public var bytes: Int64?
    public var sha256: String?

    public init(name: String, bytes: Int64? = nil, sha256: String? = nil) {
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// A file Cairn will actually fetch, with its resolved URL.
public struct ModelFileDescriptor: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var url: URL
    public var bytes: Int64?
    public var sha256: String?

    public init(name: String, url: URL, bytes: Int64? = nil, sha256: String? = nil) {
        self.name = name
        self.url = url
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// Decides which published files make up one runnable MLX model.
///
/// A repository carries far more than a model needs — dataset shards, GGUF copies, notebooks,
/// `.gitattributes` — so the plan takes only what the runtime reads: the config, the tokenizer
/// assets, and the safetensors weights (or the shard index plus its shards). Everything else is
/// left on the server, which matters on a phone plan more than it matters on a desktop.
public enum ModelFilePlan {
    static let requiredExactNames: [String] = ["config.json"]
    static let weightSuffix = ".safetensors"
    static let indexSuffix = "model.safetensors.index.json"
    static let tokenizerPrefixes = ["tokenizer", "vocab", "special_tokens_map", "generation_config", "preprocessor_config", "processor_config"]
    static let skippedNames: Set<String> = [".gitattributes", "README.md", "README"]

    public static func select(
        from listing: [ModelFileListing],
        repoID: String
    ) -> [ModelFileDescriptor] {
        var chosen: [ModelFileListing] = []
        for file in listing where !skippedNames.contains(file.name) {
            if isWanted(file.name) { chosen.append(file) }
        }
        return chosen.compactMap { file in
            guard let url = HuggingFaceEndpoints.fileURL(repoID: repoID, name: file.name) else { return nil }
            return ModelFileDescriptor(name: file.name, url: url, bytes: file.bytes, sha256: file.sha256)
        }
    }

    public static func isWanted(_ name: String) -> Bool {
        let lower = name.lowercased()
        if skippedNames.contains(lower) { return false }
        if lower.hasSuffix(indexSuffix) { return true }
        if lower.hasSuffix(weightSuffix) { return true }
        if requiredExactNames.contains(lower) { return true }
        return tokenizerPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    /// The total bytes the plan will pull, or nil when any file went unlisted. A partial total must
    /// not be presented as a fit figure, because the fit check would then be a guess.
    public static func totalBytes(of plan: [ModelFileDescriptor]) -> Int64? {
        var total: Int64 = 0
        for file in plan {
            guard let bytes = file.bytes else { return nil }
            let (next, overflow) = total.addingReportingOverflow(bytes)
            if overflow { return nil }
            total = next
        }
        return plan.isEmpty ? nil : total
    }

    /// Tolerant decode of the published listing. Both shapes the API has used are accepted
    /// (`{path,size,lsha}` and `{filename,size,sha256}`); anything unrecognisable yields an empty
    /// listing, which the caller shows as "this repository has no readable file list".
    public static func listing(from data: Data) -> [ModelFileListing] {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let entries = root as? [[String: Any]]
        else { return [] }

        return entries.compactMap { entry in
            guard let name = (entry["path"] as? String) ?? (entry["filename"] as? String) else { return nil }
            let bytes = (entry["size"] as? NSNumber)?.int64Value
            let digest = (entry["lsha"] as? String) ?? (entry["sha256"] as? String)
            return ModelFileListing(name: name, bytes: bytes, sha256: digest)
        }
    }
}
