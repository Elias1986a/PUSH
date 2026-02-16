// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PUSH",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PUSH", targets: ["PUSH"])
    ],
    dependencies: [
        // WhisperKit for speech-to-text
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),

        // Moonshine for speech-to-text (edge-optimized ASR)
        .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", from: "0.0.48"),

        // llama.cpp Swift bindings (Swift-friendly wrapper)
        .package(url: "https://github.com/ShenghaiWang/SwiftLlama.git", branch: "main"),

        // Launch at login
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "PUSH",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Moonshine", package: "moonshine-swift"),
                .product(name: "SwiftLlama", package: "SwiftLlama"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern")
            ],
            path: "PUSH",
            exclude: [
                "PUSH.entitlements",
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Concurrency diagnostics (debug-only) to surface actor/thread violations early.
                .unsafeFlags(
                    [
                        "-Xfrontend", "-warn-concurrency",
                        "-Xfrontend", "-enable-actor-data-race-checks",
                        "-Xfrontend", "-strict-concurrency=complete"
                    ],
                    .when(configuration: .debug)
                )
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .unsafeFlags([
                    "-Xlinker", "-force_load",
                    "-Xlinker", ".build/artifacts/moonshine-swift/Moonshine/Moonshine.xcframework/macos-arm64_x86_64/libmoonshine.a"
                ])
            ]
        )
    ]
)
