// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Sparkle is a binary xcframework; SPM links it via @rpath but doesn't embed it
// in the test bundle, so `swift test` needs an rpath to the resolved artifact.
let sparkleArtifactPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64")
    .path

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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),

        // Moonshine for speech-to-text (edge-optimized ASR)
        .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", from: "0.0.48"),

        // FluidAudio for Parakeet TDT v2 speech-to-text (CoreML/ANE)
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),

        // Qwen3-ASR speech-to-text (MLX + CoreML hybrid)
        // TODO: Re-enable once MLX metallib bundling is resolved
        // .package(url: "https://github.com/soniqo/speech-swift.git", from: "0.0.8"),

        // Launch at login
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),

        // Sparkle for in-app auto-updates (Developer ID + notarized builds)
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "PUSH",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Moonshine", package: "moonshine-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                // .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "Sparkle", package: "Sparkle")
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
        ),
        .testTarget(
            name: "PUSHTests",
            dependencies: ["PUSH"],
            path: "Tests/PUSHTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sparkleArtifactPath])
            ]
        )
    ]
)
