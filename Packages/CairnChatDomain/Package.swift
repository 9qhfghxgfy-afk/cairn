// swift-tools-version: 6.0

// tools-version 6.0 means every target in this package compiles in Swift 6
// language mode (strict concurrency complete) by default. No opt-in flag needed.
// Keep this package free of SwiftUI, SwiftData, and networking so the chat tree
// and the hybrid engine stay unit-testable on the macOS host with `swift test`.

import PackageDescription

let package = Package(
    name: "CairnChatDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnChatDomain", targets: ["CairnChatDomain"]),
    ],
    targets: [
        .target(name: "CairnChatDomain"),
        .testTarget(
            name: "CairnChatDomainTests",
            dependencies: ["CairnChatDomain"]
        ),
    ]
)
