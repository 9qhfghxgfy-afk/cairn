// swift-tools-version: 6.0

// The only module allowed to speak URLSession / talk to a socket. Everything it
// needs to reason about (profiles, network class, codecs, line framing) lives in
// the pure CairnChatDomain package, so this module is thin plumbing only.
// Kept out of the "pure" package on purpose: no unit test here needs a simulator,
// but nothing here is provable without a stub transport.

import PackageDescription

let package = Package(
    name: "CairnProviderRemote",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnProviderRemote", targets: ["CairnProviderRemote"]),
    ],
    dependencies: [
        .package(path: "../CairnChatDomain"),
    ],
    targets: [
        .target(
            name: "CairnProviderRemote",
            dependencies: [
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
        .testTarget(
            name: "CairnProviderRemoteTests",
            dependencies: [
                "CairnProviderRemote",
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
    ]
)
