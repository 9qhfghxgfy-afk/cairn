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
// Pin: `mlx-swift-lm` **2.31.3**, with `mlx-swift` pinned to **0.31.4**. 0.31.4 is the newest 0.31.x whose
// manifest CI's pinned toolchain can read: 0.31.5 and 0.31.6 declare
// `swift-tools-version: 6.3;(experimentalCGen)`, which Xcode_26.6 rejects while it parses the manifest, so a
// `CAIRN_MLX=1` build pinned to either of those dies during dependency resolution before any Cairn source
// is compiled. 0.31.4 declares 5.12 and still satisfies the dependency's own
// `.upToNextMinor(from: "0.31.3")`, so nothing about the range the runtime asks for has moved. Products
// used: MLXLLM, MLXLMCommon. The same pair is declared in `project.yml` at the same pins, because two exact
// pins of one URL that disagree make the graph unsatisfiable.
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
// DEFAULT — the runtime is linked. This was inverted on 2026-11-21, and the reason is a phone, not a
// preference: Xcode's ⌘R does not pass the authoring shell's environment into SwiftPM's manifest
// evaluation, so a default-on-flag meant every build a person actually ran from the Xcode GUI resolved
// this package with MLX absent. `NativeRuntimeBuild.mlxIsLinked` then read false — correctly, since the
// runtime genuinely was not in the binary — and the Servers screen told an iPhone 15 Pro holding
// gigabytes of downloaded weights that the on-device runtime was not in this build. A flag nobody can set
// from the one place the app is built is not a configuration, it is a silent downgrade.
//
// So the flag is now an opt-out, and the opt-out is used only where a lane is deliberately about the
// excluded shape or is time-boxed:
//   (nothing set)      link MLX 2.31.3 — Xcode ⌘R, `Scripts/ci.sh device`, and the `.ipa` lane
//   CAIRN_SKIP_MLX=1   no MLX — the host native-test lane and the simulator build/test lanes, which are
//                      fast on purpose; linking a vendored C++ and Metal core inside those time boxes is
//                      the CI's clock to decide, not this manifest's
// `CAIRN_MLX=1` is still accepted and means nothing on its own now, so an older invocation cannot
// silently flip a lane back to the excluded shape.
//
// What is still owed: MLX has been compiled for the macOS host, and the device lane is the build that
// carries it into a binary a person installs. Nobody has compiled it for the arm64 iOS Simulator, and no
// device run has yet been observed on a phone with this inversion in place — which is why the simulator
// lanes keep the opt-out and ROADMAP.md carries the gap rather than this comment hiding it.
//
// Logging rule: nothing here writes prompt text, response text or secrets. Typed metadata only.

import PackageDescription

private let skipMLX = Context.environment["CAIRN_SKIP_MLX"] == "1"

private var mlxDependencies: [Package.Dependency] {
    guard !skipMLX else { return [] }
    return [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
    ]
}

private var mlxProducts: [Target.Dependency] {
    guard !skipMLX else { return [] }
    return [
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        // `MLX` itself, not only the language-model layer above it. The runtime's buffer pool is what
        // turns a multi-gigabyte load into a jetsam kill on a phone, and the only lever over that pool
        // — `Memory.cacheLimit`, `Memory.clearCache()`, and the `Memory.cacheMemory` reading that
        // shows what the pool is holding — lives in this product. A cache budget that cannot be set is
        // a budget that does not exist.
        .product(name: "MLX", package: "mlx-swift"),
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
