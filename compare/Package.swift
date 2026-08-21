// swift-tools-version: 6.0
import PackageDescription

/// A local developer tool, deliberately its own package: nothing here ships, and the
/// app's release build never sees it.
let package = Package(
    name: "compare",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "compare",
            dependencies: [
                .product(name: "PUSHCore", package: "PUSH")
            ],
            path: "Sources/compare",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
