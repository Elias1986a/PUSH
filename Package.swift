// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Sparkle is a binary xcframework; SPM links it via @rpath but doesn't embed it
// in the test bundle, so `swift test` needs an rpath to the resolved artifact.
// The Moonshine static archive, as an absolute path. It used to be written relative
// to the working directory, which resolves correctly only when the build is run from
// the repo root — the comparison tool builds PUSHCore from its own directory and would
// otherwise fail to link.
let moonshineArchivePath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".build/artifacts/moonshine-swift/Moonshine/Moonshine.xcframework/macos-arm64_x86_64/libmoonshine.a")
    .path

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
        .executable(name: "PUSH", targets: ["PUSH"]),
        // The engines and the text pipeline, so the local comparison tool can drive the
        // same code the app runs rather than a second copy of it.
        .library(name: "PUSHCore", targets: ["PUSHCore"])
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
        // Engines + text post-processing. No SwiftUI, no AppState, no resources —
        // adding a resource here would introduce Bundle.module, which fatal-asserts in
        // distribution builds. The app bundle owns the resources.
        .target(
            name: "PUSHCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                // v0.0.48 names this product "Moonshine"; v0.1.3 renamed it to
                // "MoonshineVoice". Any package depending on PUSHCore must pin the same
                // revision — compare/Package.resolved is copied from this package's for
                // exactly that reason.
                .product(name: "Moonshine", package: "moonshine-swift"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "PUSHCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                // Follows MoonshineEngine into this target. Moonshine ships a static
                // archive whose symbols are only referenced dynamically, so without
                // -force_load the linker drops them and the app fails at runtime rather
                // than at build time.
                .unsafeFlags([
                    "-Xlinker", "-force_load",
                    "-Xlinker", moonshineArchivePath
                ])
            ]
        ),
        .executableTarget(
            name: "PUSH",
            dependencies: [
                "PUSHCore",
                // Only FluidAudio remains: SileroVAD lives in the app. The engines and
                // their SDKs moved to PUSHCore.
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
                    "-Xlinker", moonshineArchivePath
                ])
            ]
        ),
        .testTarget(
            name: "PUSHTests",
            dependencies: ["PUSH", "PUSHCore"],
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
