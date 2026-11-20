import Foundation

/// The curated on-device MLX library.
///
/// Kept in step with `CairnInferenceLocal.OnDeviceCatalog`, which is the download-plumbing half of
/// the same library — weights, context ceiling, checksum plan. `ModelCatalogAlignmentTests` in that
/// package fails if an entry is in one list and not the other, or if the two disagree on a date or a
/// size, which is what stops a card advertising a model the downloader has no plan for.
///
/// `downloadBytes` is the published total of the files Cairn actually pulls: the weights plus the
/// tokenizer and config assets. For the entries curated before this screen existed it is the
/// published weight total, which is within a few megabytes of that — the alignment test holds the two
/// lists inside that band rather than pretending they are the same measurement.
///
/// Capability badges come from what the publisher states: a `vision_config` or `audio_config` block in
/// the repository's own `config.json`, or the capability tag the publisher lists. A repository that
/// states nothing gets no badge, which is why several rows here carry none.
extension ModelCatalog {
    static let onDeviceRows: [LocalCatalogRow] = [
        LocalCatalogRow(
            repoID: "mlx-community/Qwen3.5-2B-6bit", displayName: "Qwen 3.5 2B",
            summary: "A general assistant small enough to hold on a phone, with a long stated "
                + "context and a vision input block in its own config.",
            parameterSize: "2B", quantization: "6-bit", downloadBytes: 2_219_390_841,
            contextLength: 262_144, capabilityLabels: ["Vision"],
            addedOn: day(2026, 3, 2), provider: "Qwen", series: "Qwen 3.5",
            sortOrder: 0, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen3.5-4B-MLX-4bit", displayName: "Qwen 3.5 4B",
            summary: "The step up in the same family: more room to reason, and the largest build "
                + "here that still fits an 8 GB phone with its context kept modest.",
            parameterSize: "4B", quantization: "4-bit", downloadBytes: 3_061_120_936,
            contextLength: 262_144, capabilityLabels: ["Vision"],
            addedOn: day(2026, 3, 2), provider: "Qwen", series: "Qwen 3.5",
            sortOrder: 1, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/gemma-4-e2b-it-4bit", displayName: "Gemma 4 E2B",
            summary: "A compact multimodal build whose published config carries vision and audio "
                + "blocks, so images and sound belong to the same turn as the text.",
            parameterSize: "E2B", quantization: "4-bit", downloadBytes: 3_583_069_162,
            contextLength: 131_072, capabilityLabels: ["Vision", "Audio"],
            addedOn: day(2026, 4, 2), provider: "Google", series: "Gemma 4",
            sortOrder: 2, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/gemma-4-e4b-it-4bit", displayName: "Gemma 4 E4B",
            summary: "The larger of the two compact multimodal builds. Read the memory warning "
                + "before downloading it to a phone with little headroom.",
            parameterSize: "E4B", quantization: "4-bit", downloadBytes: 5_179_222_013,
            contextLength: 131_072, capabilityLabels: ["Vision", "Audio"],
            addedOn: day(2026, 4, 2), provider: "Google", series: "Gemma 4",
            sortOrder: 3, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/MiniCPM5-1B-4bit", displayName: "MiniCPM5 1B",
            summary: "The smallest download in the library, and the one entry here whose publisher "
                + "states tool calling at this size.",
            parameterSize: "1B", quantization: "4-bit", downloadBytes: 617_961_831,
            capabilityLabels: ["Tools"],
            addedOn: day(2026, 5, 26), provider: "OpenBMB", series: "MiniCPM5",
            sortOrder: 4, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen3-4B-MLX-4bit", displayName: "Qwen3 4B",
            summary: "Reasoning and tool calling in one 4-bit build, which is what makes a tool "
                + "turn work entirely on this phone.",
            parameterSize: "4B", quantization: "4-bit", downloadBytes: 2_400_000_000,
            contextLength: 40_960, capabilityLabels: ["Thinking", "Tools"],
            addedOn: day(2025, 5, 1), provider: "Qwen", series: "Qwen3",
            sortOrder: 5, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Llama-3.2-3B-Instruct-4bit", displayName: "Llama 3.2 3B Instruct",
            summary: "A middle-size instruct build with a long stated context. Nothing about it is "
                + "published as multimodal, so it carries no badge.",
            parameterSize: "3B", quantization: "4-bit", downloadBytes: 1_900_000_000,
            contextLength: 131_072,
            addedOn: day(2024, 9, 25), provider: "Meta", series: "Llama 3.2",
            sortOrder: 6, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Llama-3.2-1B-Instruct-4bit", displayName: "Llama 3.2 1B Instruct",
            summary: "The quickest thing here to download and to load, for a phone that wants "
                + "answers rather than depth.",
            parameterSize: "1B", quantization: "4-bit", downloadBytes: 700_000_000,
            contextLength: 131_072,
            addedOn: day(2024, 9, 25), provider: "Meta", series: "Llama 3.2",
            sortOrder: 7, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen2-VL-2B-Instruct-4bit", displayName: "Qwen2-VL 2B Instruct",
            summary: "An older vision build, kept because it is smaller than the newer multimodal "
                + "ones and does the same job on a photo.",
            parameterSize: "2B", quantization: "4-bit", downloadBytes: 1_700_000_000,
            contextLength: 32_768, capabilityLabels: ["Vision"],
            addedOn: day(2024, 10, 20), provider: "Qwen", series: "Qwen2-VL",
            sortOrder: 8, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/gemma-2-2b-it-4bit", displayName: "Gemma 2 2B Instruct",
            summary: "A short-context text build. Its advertised ceiling is modest, so a long chat "
                + "reaches it sooner than the others here.",
            parameterSize: "2B", quantization: "4-bit", downloadBytes: 1_600_000_000,
            contextLength: 8_192,
            addedOn: day(2024, 8, 1), provider: "Google", series: "Gemma 2",
            sortOrder: 9, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Phi-3.5-mini-instruct-4bit", displayName: "Phi-3.5 Mini Instruct",
            summary: "A text model tuned for instruction following, with a long stated context that "
                + "only helps if the phone has the memory to hold it.",
            parameterSize: "3.8B", quantization: "4-bit", downloadBytes: 2_200_000_000,
            contextLength: 131_072,
            addedOn: day(2024, 8, 21), provider: "Microsoft", series: "Phi-3.5",
            sortOrder: 10, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", displayName: "Qwen2.5 1.5B Instruct",
            summary: "A small general build from the previous Qwen line, still a reasonable first "
                + "download on a phone with little space.",
            parameterSize: "1.5B", quantization: "4-bit", downloadBytes: 1_000_000_000,
            contextLength: 32_768,
            addedOn: day(2024, 10, 12), provider: "Qwen", series: "Qwen2.5",
            sortOrder: 11, origin: .onDevice
        ),
        LocalCatalogRow(
            repoID: "mlx-community/Llama-3.1-8B-Instruct-4bit", displayName: "Llama 3.1 8B Instruct",
            summary: "The largest build in this library. The memory warning is worth reading twice "
                + "before downloading it to an 8 GB phone.",
            parameterSize: "8B", quantization: "4-bit", downloadBytes: 4_600_000_000,
            contextLength: 131_072,
            addedOn: day(2024, 7, 23), provider: "Meta", series: "Llama 3.1",
            sortOrder: 12, origin: .onDevice
        ),
    ]
}
