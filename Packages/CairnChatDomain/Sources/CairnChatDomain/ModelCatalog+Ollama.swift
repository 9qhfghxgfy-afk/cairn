import Foundation

/// The curated Ollama library tags.
///
/// These are names to *ask a server for*, not files this phone downloads. Each `repoID` is the exact
/// tag from the Ollama library, which is what the pull request is sent: asking for `qwen3:4b` rather
/// than a bare `qwen3` is what keeps a server from choosing a quantization this screen never showed
/// the person.
///
/// Sizes are the figures the library publishes, stored as bytes. Capabilities are copied from the
/// capability filter the library itself lists for a family — `tools`, `thinking`, `vision` — and
/// nothing beyond it; the 1B Gemma tag is listed as text input, so it carries no vision badge even
/// though the family does. Where the library's default tag demonstrably *is* a named quantization,
/// that quantization is stated; where it is not demonstrable the field stays empty rather than
/// assumed, because a popular model's default tag is not reliably the 4-bit build.
extension ModelCatalog {
    static let ollamaRows: [LocalCatalogRow] = [
        LocalCatalogRow(
            repoID: "qwen3:4b", displayName: "Qwen3 4B",
            summary: "Reasoning and tool calling on the server, at the size most often picked for a "
                + "single-GPU machine.",
            parameterSize: "4B", downloadBytes: 2_500_000_000,
            capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2026, 10, 12), provider: "Qwen", series: "Qwen3",
            sortOrder: 0, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "gemma3:4b", displayName: "Gemma 3 4B",
            summary: "The library lists this family as taking images as well as text, at a size that "
                + "runs on a modest server.",
            parameterSize: "4B", downloadBytes: 3_400_000_000, capabilityLabels: ["Vision"],
            addedOn: day(2026, 10, 12), provider: "Google", series: "Gemma 3",
            sortOrder: 1, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "llama3.2:3b", displayName: "Llama 3.2 3B",
            summary: "A widely hosted instruct build the library lists with tool calling, and the "
                + "usual first pull onto a small server.",
            parameterSize: "3B", downloadBytes: 2_000_000_000, capabilityLabels: ["Tools"],
            addedOn: day(2026, 10, 12), provider: "Meta", series: "Llama 3.2",
            sortOrder: 2, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "qwen3:1.7b", displayName: "Qwen3 1.7B",
            summary: "The smaller reasoning build, published by the library as a 4-bit default at "
                + "this size.",
            parameterSize: "1.7B", quantization: "q4_K_M", downloadBytes: 1_400_000_000,
            capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2026, 10, 12), provider: "Qwen", series: "Qwen3",
            sortOrder: 3, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "llama3.2:1b", displayName: "Llama 3.2 1B",
            summary: "The smallest tag here. Cheap to pull onto a server, and quick to load for a "
                + "short answer.",
            parameterSize: "1B", downloadBytes: 1_300_000_000, capabilityLabels: ["Tools"],
            addedOn: day(2026, 10, 12), provider: "Meta", series: "Llama 3.2",
            sortOrder: 4, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "qwen2.5-coder:7b", displayName: "Qwen2.5-Coder 7B",
            summary: "A code-tuned build the library lists with tool calling, for a server with room "
                + "for a second model beside a general one.",
            parameterSize: "7B", downloadBytes: 4_700_000_000, capabilityLabels: ["Tools"],
            addedOn: day(2026, 10, 5), provider: "Qwen", series: "Qwen2.5-Coder",
            sortOrder: 5, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "gemma3:1b", displayName: "Gemma 3 1B",
            summary: "The small Gemma tag. The library lists text input for this size, so it carries "
                + "no vision badge even though the family does.",
            parameterSize: "1B", quantization: "q4_K_M", downloadBytes: 806_000_000,
            addedOn: day(2026, 10, 5), provider: "Google", series: "Gemma 3",
            sortOrder: 6, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "deepseek-r1:1.5b", displayName: "DeepSeek-R1 1.5B",
            summary: "A reasoning build distilled to a size a server can hold, and the cheapest way "
                + "to see a thinking panel from a remote engine.",
            parameterSize: "1.5B", downloadBytes: 1_100_000_000,
            capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2026, 10, 5), provider: "DeepSeek", series: "DeepSeek-R1",
            sortOrder: 7, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "phi4-mini:3.8b", displayName: "Phi-4 Mini 3.8B",
            summary: "A compact instruct build the library lists with tool calling, sized between the "
                + "small tags and the 7B ones.",
            parameterSize: "3.8B", downloadBytes: 2_500_000_000, capabilityLabels: ["Tools"],
            addedOn: day(2026, 9, 28), provider: "Microsoft", series: "Phi-4",
            sortOrder: 8, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "qwen3:8b", displayName: "Qwen3 8B",
            summary: "The larger reasoning tag. Pull it onto a server with the memory for it; a server "
                + "that cannot hold it will say so when asked.",
            parameterSize: "8B", downloadBytes: 5_200_000_000,
            capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2026, 9, 28), provider: "Qwen", series: "Qwen3",
            sortOrder: 9, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "gemma3:12b", displayName: "Gemma 3 12B",
            summary: "The bigger multimodal tag in this list, for a server that has the room and will "
                + "be asked about documents and photographs.",
            parameterSize: "12B", downloadBytes: 8_200_000_000, capabilityLabels: ["Vision"],
            addedOn: day(2026, 9, 28), provider: "Google", series: "Gemma 3",
            sortOrder: 10, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "deepseek-r1:8b", displayName: "DeepSeek-R1 8B",
            summary: "The larger distilled reasoning tag, which trades a long pull for a thinking "
                + "panel worth reading.",
            parameterSize: "8B", downloadBytes: 5_200_000_000,
            capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2026, 9, 21), provider: "DeepSeek", series: "DeepSeek-R1",
            sortOrder: 11, origin: .ollamaLibrary
        ),
        LocalCatalogRow(
            repoID: "qwen2.5-coder:3b", displayName: "Qwen2.5-Coder 3B",
            summary: "The small code tag, cheap enough to pull to try whether a code-tuned answer "
                + "suits the work better than a general model does.",
            parameterSize: "3B", downloadBytes: 1_900_000_000, capabilityLabels: ["Tools"],
            addedOn: day(2026, 9, 21), provider: "Qwen", series: "Qwen2.5-Coder",
            sortOrder: 12, origin: .ollamaLibrary
        ),
    ]
}
