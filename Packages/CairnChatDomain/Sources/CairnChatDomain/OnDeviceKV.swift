import Foundation

/// The one bound on an on-device attention cache, stated in the domain so the engine that hands it
/// to a runtime and the preflight that sizes a load cannot drift apart.
///
/// Two modules have to agree on this figure and neither may import the other: `CairnInferenceNative`
/// sets it as the runtime's rotating cache size, and `CairnInferenceLocal` counts the bytes it will
/// cost when it decides whether a model fits in the memory this process still has. A second copy of
/// the number is a number that eventually disagrees, and a disagreement of that kind is an
/// out-of-memory kill rather than an off-by-one.
///
/// What this is **not**: a context window, and not a knob. mlx-swift's `GenerateParameters.maxKVSize`
/// is documented as "Maximum size of the key-value cache. Old entries (except the first 4 tokens)
/// will be overwritten. When set, uses RotatingKVCache instead of KVCacheSimple" — so past this many
/// tokens the model stops attending to its own oldest history, which is the honest cost of a bound
/// that keeps an 8 GB phone out of a jetsam kill. The window the model was trained for is a different
/// fact, and `MLXNativeProvider.capabilities` therefore keeps `contextLengthAdjustable` false.
public enum OnDeviceKV {
    /// Tokens of attention a local model may accumulate in one turn.
    ///
    /// 2,048 is deliberately modest. For the shapes in the curated on-device catalog this is tens of
    /// megabytes of cache rather than the gigabytes an uncapped cache reaches on a long conversation,
    /// and it is the figure the memory-fit estimate is computed at, so the warning a person reads
    /// before downloading describes the configuration Cairn will actually run.
    public static let tokenCap = 2048

    /// Tokens a rotating cache never overwrites.
    ///
    /// Read out of the runtime's own documented behaviour rather than invented: the first few turns
    /// of a prompt stay resident when the cache rotates, so a system prompt is not the first thing
    /// the model loses. Recorded here so a future reader does not mistake `tokenCap` for the whole
    /// usable window.
    public static let rotatingHeadroomTokens = 4
}
