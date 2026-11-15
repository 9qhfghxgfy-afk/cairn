// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CairnPersistence",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CairnPersistence", targets: ["CairnPersistence"]),
    ],
    dependencies: [
        .package(path: "../CairnChatDomain"),
    ],
    targets: [
        .target(
            name: "CairnPersistence",
            dependencies: [
                .product(name: "CairnChatDomain", package: "CairnChatDomain"),
            ]
        ),
    ]
)
