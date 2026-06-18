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
        .library(
            name: "RecipeScalerCore",
            targets: ["RecipeScalerCore"]
        ),
    ],
    dependencies: [
        // WebSocket support
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),

        // Keychain for secure storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),

        // Snapshot testing for UI regression checks
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),

        // SQLite storage for Y.Doc snapshots
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Binary module YrsC (libyrs FFI).
        // Module name comes from `module.modulemap` inside the xcframework;
        // the on-disk folder is named `YrsXCFramework.xcframework`.
        .binaryTarget(
            name: "YrsC",
            path: "Frameworks/YrsXCFramework.xcframework"
        ),

        // Source target RecipeScalerCore. Shared domain logic (networking,
        // import, auth, snapshots). Only depends on system frameworks.
        .target(
            name: "RecipeScalerCore",
            dependencies: [],
            path: "RecipeScalerCore",
            exclude: [
                ".DS_Store",
                "Import/.DS_Store",
            ],
            resources: [
                .process("Resources"),
                .copy("Export/Native/schemas"),
            ]
        ),

        // Main app target. Now declares its true dependencies on Core and YrsC.
        .target(
            name: "RecipeScalerNative",
            dependencies: [
                "RecipeScalerCore",
                "YrsC",
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "RecipeScalerNative",
            exclude: [
                "Info.plist",
                "Resources/Localizable.xcstrings"
            ],
            resources: [
                .process("Resources")
            ]
        ),

        // Tests: `@testable import RecipeScalerCore` and `import YrsC` need both
        // targets as explicit dependencies of the test target.
        .testTarget(
            name: "RecipeScalerNativeTests",
            dependencies: [
                "RecipeScalerNative",
                "RecipeScalerCore",
                "YrsC",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "RecipeScalerNativeTests"
        ),
    ]
)
