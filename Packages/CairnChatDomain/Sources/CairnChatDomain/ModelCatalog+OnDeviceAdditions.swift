import Foundation

/// The MLX builds added to the on-device library after the first pass.
///
/// Same rule as `onDeviceRows`: every number here was read from the named repository's own API record
/// on 2026-11-20 — the byte total is the sum of the files Cairn actually fetches (weights plus the
/// config and tokenizer assets `ModelFilePlan` selects), the context is the repository's own
/// `max_position_embeddings`, and a badge appears only when the repository's `config.json` carries the
/// block that states it. A repository that states nothing gets no badge, which is why three of these
/// rows carry none.
extension ModelCatalog {
    static let onDeviceAdditions: [LocalCatalogRow] = [
        LocalCatalogRow(
            repoID: "mlx-community/Qwen3.5-2B-4bit", displayName: "Qwen 3.5 2B (4-bit)",
            summary: "The 4-bit build of the same 2B assistant — the smaller download of the two Qwen "
                + "3.5 builds here, with the long context and the vision input block its config states.",
            parameterSize: "2B", quantization: "4-bit", downloadBytes: 1_749_071_936,
            contextLength: 262_144, capabilityLabels: ["Vision"],
            addedOn: day(2026, 3, 2), provider: "Qwen", series: "Qwen 3.5",
            sortOrder: 13, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen3.5-4B-4bit", displayName: "Qwen 3.5 4B (4-bit)",
            summary: "The 4-bit 4B build, stated at the same 262,144-token context as its smaller "
                + "sibling. Read the memory warning before installing it on an 8 GB phone.",
            parameterSize: "4B", quantization: "4-bit", downloadBytes: 3_061_121_321,
            contextLength: 262_144, capabilityLabels: ["Vision"],
            addedOn: day(2026, 3, 2), provider: "Qwen", series: "Qwen 3.5",
            sortOrder: 14, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/gemma-3-4b-it-4bit", displayName: "Gemma 3 4B Instruct",
            summary: "The instruct build of Gemma 3 at 4-bit. Its own config carries a vision block; "
                + "no context figure is published at the top level, so none is claimed here.",
            parameterSize: "4B", quantization: "4-bit", downloadBytes: 3_439_894_985,
            capabilityLabels: ["Vision"],
            addedOn: day(2025, 3, 21), provider: "Google", series: "Gemma 3",
            sortOrder: 15, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            displayName: "Qwen2.5-Coder 3B Instruct",
            summary: "A code-tuned MLX build for a phone that writes code with you. Its published "
                + "context is modest, so a long file pasted in reaches the ceiling sooner.",
            parameterSize: "3B", quantization: "4-bit", downloadBytes: 1_747_849_128,
            contextLength: 32_768,
            addedOn: day(2024, 11, 11), provider: "Qwen", series: "Qwen2.5-Coder",
            sortOrder: 16, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
            displayName: "DeepSeek-R1 Distill 1.5B",
            summary: "The distilled reasoning build, and the smallest way to get a thinking panel "
                + "written on this phone rather than fetched from a server.",
            parameterSize: "1.5B", quantization: "4-bit", downloadBytes: 1_011_384_346,
            contextLength: 131_072, capabilityLabels: ["Thinking"],
            addedOn: day(2025, 2, 26), provider: "DeepSeek", series: "DeepSeek-R1",
            sortOrder: 17, origin: .onDevice
        ),
    ]
}
