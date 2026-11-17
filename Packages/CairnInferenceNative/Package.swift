// swift-tools-version: 6.0

// CairnInferenceNative — the MLX runtime, quarantined.
//
// SWIFT 5 LANGUAGE MODE, on purpose. `mlx-swift-lm` is a tools-6.2 package that carries C++
// interop (a vendored grammar engine) and macro plugins, and that surface is not
// strict-concurrency clean. A Swift 6 target in `complete` strict mode that imports it cannot
// compile. Rather than relax strict concurrency across the app or the domain, the import is
// isolated HERE: this is the only module in Cairn allowed to import MLX, and it is actor-wrapped
// at its boundary, so every module on the other side of that boundary — CairnChatDomain,
// CairnAppUI, CairnInferenceLocal — stays Swift 6 strict and never sees a MLX type.
//
// Pin: `mlx-swift-lm` 3.32.3, with `mlx-swift` pinned to the 0.32.3 it resolves to, so a
// transitive `upToNextMinor` cannot quietly move the runtime under a milestone that was
// verified against a different one. Products used: MLXLLM, MLXLMCommon.
//
// ESCAPE HATCH — `CAIRN_SKIP_MLX=1` drops the MLX dependency entirely and compiles the same
// sources with the runtime absent. It exists because this dependency compiles swift-syntax
// macros and a vendored C++ engine from source, which is a large wall-clock and memory cost on
// an 8 GB authoring Mac and on a shared CI runner. With the hatch set, the provider still
// conforms to `InferenceProvider`, the template parser and its tests are unchanged, and the
// provider reports its own unavailability honestly instead of pretending to be a working engine.
//
// DEFAULT — the runtime is linked only when `CAIRN_MLX=1` is set, because that is the one
// configuration this milestone could not prove builds inside a CI time box or on the authoring
// machine. `CAIRN_SKIP_MLX=1` forces the exclusion even if `CAIRN_MLX` is set. So:
//   CAIRN_MLX=1        link MLX 3.32.3 (device / release build; needs the time and the RAM)
//   (nothing set)      no MLX — what CI and the simulator build use
//   CAIRN_SKIP_MLX=1   no MLX, forced
// The gap this leaves is recorded in ROADMAP.md, not hidden here.
//
// Logging rule: nothing here writes prompt text, response text or secrets. Typed metadata only.

import PackageDescription

private let wantsMLX = Context.environment["CAIRN_MLX"] == "1"
private let skipMLX = Context.environment["CAIRN_SKIP_MLX"] == "1" || !wantsMLX

private var mlxDependencies: [Package.Dependency] {
    guard !skipMLX else { return [] }
    return [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
    ]
}

private var mlxProducts: [Target.Dependency] {
    guard !skipMLX else { return [] }
    return [
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
    ]
}

let package = Package(
    name: "CairnInferenceNative",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnInferenceNative", targets: ["CairnInferenceNative"]),
    ],
    dependencies: [
        .package(path: "../CairnChatDomain"),
    ] + mlxDependencies,
    targets: [
        .target(
            name: "CairnInferenceNative",
            dependencies: [
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ] + mlxProducts,
            // The one Swift 5 island in Cairn. See the header above.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CairnInferenceNativeTests",
            dependencies: [
                "CairnInferenceNative",
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
