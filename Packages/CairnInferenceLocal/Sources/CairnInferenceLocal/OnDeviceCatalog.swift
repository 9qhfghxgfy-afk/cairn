import Foundation

/// Cairn's curated on-device library.
///
/// Static on purpose. Browsing a library must work offline and must not be a network call the user
/// did not ask for; only an actual download reaches Hugging Face, and that path carries the
/// public-internet opt-in and the outbound badge.
///
/// Every row is copied from what the named repository publishes. `weightsBytes` is that repo's
/// published weight total rounded to the nearest hundred megabyte, and the fit estimate is
/// recomputed from the bytes that really land on disk. Attention fields stay nil here because they
/// belong to the model's own `config.json`, which is read after download — inventing an architecture
/// here would put a made-up number in a memory warning.
///
/// The list is scoped to builds an 8 GB iPhone can plausibly hold, which is why it is mostly 4-bit
/// and small. Larger repos remain reachable through the exact-name field.
public enum OnDeviceCatalog {
    /// The library curated when this module was written. The later additions live in
    /// `OnDeviceCatalog+MLX.swift`; `entries` is the one list every caller reads.
    static let baseEntries: [OnDeviceCatalogEntry] = [
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B Instruct",
            weightsBytes: 700_000_000,
            parameterSize: "1B",
            quantization: "4-bit",
            advertisedContextLength: 131_072,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 9, 25)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            displayName: "Qwen2.5 1.5B Instruct",
            weightsBytes: 1_000_000_000,
            parameterSize: "1.5B",
            quantization: "4-bit",
            advertisedContextLength: 32_768,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 10, 12)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/gemma-2-2b-it-4bit",
            displayName: "Gemma 2 2B Instruct",
            weightsBytes: 1_600_000_000,
            parameterSize: "2B",
            quantization: "4-bit",
            advertisedContextLength: 8_192,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 8, 1)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct",
            weightsBytes: 1_900_000_000,
            parameterSize: "3B",
            quantization: "4-bit",
            advertisedContextLength: 131_072,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 9, 25)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
            displayName: "Qwen2-VL 2B Instruct",
            weightsBytes: 1_700_000_000,
            parameterSize: "2B",
            quantization: "4-bit",
            advertisedContextLength: 32_768,
            defaultContextLength: 4096,
            capabilities: [.vision],
            addedToLibrary: Self.day(2024, 10, 20)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi-3.5 Mini Instruct",
            weightsBytes: 2_200_000_000,
            parameterSize: "3.8B",
            quantization: "4-bit",
            advertisedContextLength: 131_072,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 8, 21)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Qwen3-4B-MLX-4bit",
            displayName: "Qwen3 4B",
            weightsBytes: 2_400_000_000,
            parameterSize: "4B",
            quantization: "4-bit",
            advertisedContextLength: 40_960,
            defaultContextLength: 4096,
            capabilities: [.thinking, .tools],
            addedToLibrary: Self.day(2025, 5, 1)
        ),
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Llama-3.1-8B-Instruct-4bit",
            displayName: "Llama 3.1 8B Instruct",
            weightsBytes: 4_600_000_000,
            parameterSize: "8B",
            quantization: "4-bit",
            advertisedContextLength: 131_072,
            defaultContextLength: 4096,
            addedToLibrary: Self.day(2024, 7, 23)
        ),
    ]

    public static func entry(repoID: String) -> OnDeviceCatalogEntry? {
        entries.first { $0.repoID == repoID }
    }

    /// Midnight UTC, so the sort order is reproducible in a test.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
