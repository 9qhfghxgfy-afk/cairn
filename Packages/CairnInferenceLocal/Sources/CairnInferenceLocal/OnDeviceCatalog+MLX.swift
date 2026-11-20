import Foundation

/// The MLX builds added to the download library, and the one list callers read.
///
/// Kept apart from the first-pass list so each half stays readable. Extensions cannot hold stored
/// type properties, so `entries` is computed: the two halves concatenated, never re-sorted, because a
/// download list that quietly changes order between launches is a list a user cannot learn.
///
/// Sizes and contexts were read from each repository's own published record on 2026-11-20 — the byte
/// total is what Cairn's own file plan pulls (weights plus the config and tokenizer assets), and the
/// context is the repository's published `max_position_embeddings`, left nil where the repository
/// publishes none at its top level rather than filled in with a plausible number.
extension OnDeviceCatalog {
    public static var entries: [OnDeviceCatalogEntry] { baseEntries + additionalEntries }

    static let additionalEntries: [OnDeviceCatalogEntry] = [
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen3.5-2B-4bit",
            displayName: "Qwen 3.5 2B (4-bit)",
            weightsBytes: 1_749_071_936,
            parameterSize: "2B",
            quantization: "4-bit",
            advertisedContextLength: 262_144,
            defaultContextLength: 4096,
            capabilities: [.vision],
            addedToLibrary: Self.day(2026, 3, 2)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen3.5-4B-4bit",
            displayName: "Qwen 3.5 4B (4-bit)",
            weightsBytes: 3_061_121_321,
            parameterSize: "4B",
            quantization: "4-bit",
            advertisedContextLength: 262_144,
            defaultContextLength: 4096,
            capabilities: [.vision],
            addedToLibrary: Self.day(2026, 3, 2)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B Instruct",
            weightsBytes: 3_439_894_985,
            parameterSize: "4B",
            quantization: "4-bit",
            defaultContextLength: 4096,
            capabilities: [.vision],
            addedToLibrary: Self.day(2025, 3, 21)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            displayName: "Qwen2.5-Coder 3B Instruct",
            weightsBytes: 1_747_849_128,
            parameterSize: "3B",
            quantization: "4-bit",
            advertisedContextLength: 32_768,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 11, 11)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
            displayName: "DeepSeek-R1 Distill 1.5B",
            weightsBytes: 1_011_384_346,
            parameterSize: "1.5B",
            quantization: "4-bit",
            advertisedContextLength: 131_072,
            defaultContextLength: 4096,
            capabilities: [.thinking],
            addedToLibrary: Self.day(2025, 2, 26)
        ),
    ]
}
