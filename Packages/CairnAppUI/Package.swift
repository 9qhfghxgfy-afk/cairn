// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CairnAppUI",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnAppUI", targets: ["CairnAppUI"]),
    ],
    dependencies: [
        .package(path: "../CairnChatDomain"),
    ],
    targets: [
        .target(
            name: "CairnAppUI",
            dependencies: [
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
    ]
)
