// swift-tools-version: 6.0
import PackageDescription

// Isolated spike to validate MLX Metal-library (metallib) bundling on Apple
// Silicon — independent of the PUSH app. Goal: prove an MLX GPU kernel loads
// its default.metallib both via `swift run` AND from a code-signed .app bundle,
// which is the blocker that has kept MLX (Gemma audio, Qwen3-ASR) out of PUSH.
let package = Package(
    name: "mlxspike",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "mlxspike", targets: ["mlxspike"])
    ],
    dependencies: [
        // Use branch: "main" to avoid pinning a stale tag; swap to a version
        // tag (e.g. from: "0.x.y") once you confirm the latest in `swift package show-dependencies`.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "mlxspike",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift")
            ]
        )
    ]
)
