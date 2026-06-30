import Foundation
import MLX

// Minimal MLX GPU smoke test. The first GPU kernel forces MLX to load its
// compiled Metal shader library (default.metallib, shipped inside the SwiftPM
// resource bundle "mlx-swift_Cmlx.bundle"). If that library can't be located
// at runtime, MLX aborts with "Failed to load the default metallib".

print("=== MLX metallib bundling spike ===")
print("executable : \(Bundle.main.executableURL?.path ?? "?")")
print("mainBundle : \(Bundle.main.bundleURL.path)")
print("resources  : \(Bundle.main.resourceURL?.path ?? "?")")

// Diagnostic: where does the Cmlx resource bundle actually live right now?
let searchBases: [URL] = [
    Bundle.main.resourceURL,                              // .app/Contents/Resources
    Bundle.main.bundleURL.deletingLastPathComponent(),   // next to the executable (swift run / Contents/MacOS)
    Bundle.main.bundleURL                                 // the bundle itself
].compactMap { $0 }

var foundBundle = false
for base in searchBases {
    let cmlx = base.appendingPathComponent("mlx-swift_Cmlx.bundle")
    if FileManager.default.fileExists(atPath: cmlx.path) {
        foundBundle = true
        let lib = cmlx.appendingPathComponent("default.metallib")
        let hasLib = FileManager.default.fileExists(atPath: lib.path)
        print("found Cmlx bundle  : \(cmlx.path)")
        print("  default.metallib : \(hasLib ? "present ✅" : "MISSING ❌")")
    }
}
if !foundBundle {
    print("⚠️  mlx-swift_Cmlx.bundle not found in any expected location — MLX will likely fail below.")
}

print("\nrunning GPU kernel (forces metallib load)...")

// Force real GPU computation. `eval` materializes the result on-device.
let a = MLXArray((0..<4096).map { Float($0) })
let result = (a * 2 + 1).sum()
eval(result)

print("✅ SUCCESS — metallib loaded and GPU kernel executed.")
print("   result = \(result)")
