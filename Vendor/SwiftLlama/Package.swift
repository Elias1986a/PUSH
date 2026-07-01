// swift-tools-version: 6.0
// Vendored fork of https://github.com/ShenghaiWang/SwiftLlama
// Local patches for PUSH's context-aware dictionary gate:
//   1. Prompt `.raw` type — feed a fully-formed prompt, bypassing the buggy
//      built-in ChatML encoder (dropped system prompt + stray quotes).
//   2. Tokenizer `parse_special = true` — so ChatML control tokens like
//      <|im_start|> are real special tokens, not literal text.
// See Vendor/SwiftLlama/PATCHES.md.
import PackageDescription

let package = Package(
    name: "SwiftLlama",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/llama.cpp.git", revision: "b6d6c5289f1c9c677657c380591201ddb210b649")
    ],
    targets: [
        // PATCH: drop the old b5046 binary xcframework; link the llama.cpp
        // SOURCE build (b6d6c) instead, which handles the gate model correctly.
        .target(name: "SwiftLlama",
                dependencies: [
                    .product(name: "llama", package: "llama.cpp")
                ])
    ]
)
