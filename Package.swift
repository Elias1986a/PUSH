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

        // FluidAudio for Parakeet TDT v2 speech-to-text (CoreML/ANE)
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.13.6"),

        // Qwen3-ASR speech-to-text (MLX + CoreML hybrid)
        // TODO: Re-enable once MLX metallib bundling is resolved
        // .package(url: "https://github.com/soniqo/speech-swift.git", from: "0.0.8"),

        // llama.cpp Swift bindings (Swift-friendly wrapper)
        // Vendored/patched fork (see Vendor/SwiftLlama): raw-prompt type +
        // special-token tokenization for the context-aware dictionary gate.
        .package(path: "Vendor/SwiftLlama"),

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
                .product(name: "SwiftLlama", package: "SwiftLlama"),
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
        // TEMPORARY verification harness for the Phase 2 LLM gate — validates the
        // SwiftLlama prompt path against the real model. Remove before release.
        .executableTarget(
            name: "GateCheck",
            dependencies: [.product(name: "SwiftLlama", package: "SwiftLlama")],
            path: "Tools/GateCheck"
        )
    ]
)
