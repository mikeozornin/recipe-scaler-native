// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RecipeScalerNative",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RecipeScalerNative",
            targets: ["RecipeScalerNative"]
        ),
    ],
    dependencies: [
        // WebSocket support
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),

        // Keychain for secure storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),

        // Snapshot testing for UI regression checks
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),

        // BIP39 dependency removed for now (not used in code)
    ],
    targets: [
        .target(
            name: "RecipeScalerNative",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "RecipeScalerNative",
            exclude: [
                "RecipeScalerNative.xcodeproj",
                "Info.plist",
                "Resources/Localizable.xcstrings"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "RecipeScalerNativeTests",
            dependencies: [
                "RecipeScalerNative",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
