// swift-tools-version: 6.0

// On-device inference that is provable without a phone: the memory-footprint estimator, the
// single-resident eviction policy, the curated MLX catalog, the Hugging Face repo-ID rule, the
// download bookkeeping, and the Apple Foundation Models availability read.
//
// Swift 6 strict concurrency (tools 6.0 gives every target Swift 6 mode). The one thing that is
// NOT here is the MLX runtime: mlx-swift-lm carries C++ interop that is not strict-concurrency
// clean, so it lives in CairnInferenceNative in Swift 5 mode, actor-wrapped at its boundary.
// This package never imports it.
//
// Networking rule: this package owns model *downloads*, which are public-internet traffic and
// therefore opt-in + badged. No prompt text, no response text and no secret is ever logged here;
// only sizes, counts, durations and digests.

import PackageDescription

let package = Package(
    name: "CairnInferenceLocal",
    platforms: [
        // Matches CairnChatDomain's floor, which Xcode enforces across the dependency graph.
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnInferenceLocal", targets: ["CairnInferenceLocal"]),
    ],
    dependencies: [
        .package(path: "../CairnChatDomain"),
    ],
    targets: [
        .target(
            name: "CairnInferenceLocal",
            dependencies: [
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
        .testTarget(
            name: "CairnInferenceLocalTests",
            dependencies: [
                "CairnInferenceLocal",
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
    ]
)
