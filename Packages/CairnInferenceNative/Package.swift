// swift-tools-version: 6.0

// CairnInferenceNative — the MLX runtime, quarantined.
//
// SWIFT 5 LANGUAGE MODE, on purpose. `mlx-swift-lm` carries C++ interop and, on the 3.x line, macro
// plugins; that surface is not strict-concurrency clean. A Swift 6 target in `complete` strict mode that
// imports it cannot compile. Rather than relax strict concurrency across the app or the domain, the import
// is isolated HERE: this is the only module in Cairn allowed to import MLX, and it is actor-wrapped at its
// boundary, so every module on the other side of that boundary — CairnChatDomain, CairnAppUI,
// CairnInferenceLocal — stays Swift 6 strict and never sees a MLX type.
//
// Pin: `mlx-swift-lm` **2.31.3**, with `mlx-swift` pinned to **0.31.6** — the top of the 0.31.x range the
// dependency itself asks for (`.upToNextMinor(from: "0.31.3")`) — so a transitive range cannot quietly move
// the runtime under a milestone that was verified against a different one. Products used: MLXLLM,
// MLXLMCommon.
//
// Why 2.31.3 and not the 3.x line, both read from the packages' own manifests on 2026-11-19:
//   * 2.31.3 declares swift-tools-version 6.1; 3.32.3 declares 6.2 and pulls in CompilerPluginSupport, so
//     a 3.x build compiles swift-syntax macros and a vendored grammar engine from source — a large
//     wall-clock and memory cost on an 8 GB authoring Mac and on a shared CI runner.
//   * Both declare the same platform floors (macOS 14 / iOS 17), so nothing about the floor changes here.
//   * 2.31.3 is the release whose `ModelContainer` / `Generation` / `UserInput(chat:tools:)` surface
//     `MLXNativeEngine.swift` was read from and written against. A pin is a claim about an API, and that
//     file's claim is this one.
//
// ESCAPE HATCH — `CAIRN_SKIP_MLX=1` drops the MLX dependency entirely and compiles the same sources with
// the runtime absent. With the hatch set, the provider still conforms to `InferenceProvider`, the template
// parser and its tests are unchanged, and the provider reports its own unavailability honestly instead of
// pretending to be a working engine.
//
// DEFAULT — the runtime is linked only when `CAIRN_MLX=1` is set, because that is the one configuration
// this milestone has not yet proved builds inside a CI time box or on the authoring machine.
// `CAIRN_SKIP_MLX=1` forces the exclusion even if `CAIRN_MLX` is set. So:
//   CAIRN_MLX=1        link MLX 2.31.3 (device / release build; needs the time and the RAM)
//   (nothing set)      no MLX — what CI and the simulator build use
//   CAIRN_SKIP_MLX=1   no MLX, forced
// The gap this leaves is recorded in ROADMAP.md, not hidden here: the engine's call shapes have been read
// out of the 2.31.3 sources, but no compiler has yet type-checked them.
//
// Logging rule: nothing here writes prompt text, response text or secrets. Typed metadata only.

import PackageDescription

private let wantsMLX = Context.environment["CAIRN_MLX"] == "1"
private let skipMLX = Context.environment["CAIRN_SKIP_MLX"] == "1" || !wantsMLX

private var mlxDependencies: [Package.Dependency] {
    guard !skipMLX else { return [] }
    return [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.6"),
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
        // Matches CairnChatDomain's floor. A lower floor here makes Xcode reject the dependency
        // ("requires minimum platform version 18.0 ... but this target supports 17.0").
        .iOS(.v18),
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
