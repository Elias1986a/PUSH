# MLX metallib bundling spike

Isolated test to crack the blocker that has kept MLX models out of PUSH —
the `// TODO: Re-enable once MLX metallib bundling is resolved` in `Package.swift`.
Solving this unlocks **both** Gemma 3n/4 audio **and** Qwen3-ASR.

Nothing here touches the PUSH app target. Run it all on the Mac (Apple Silicon).

## The hypothesis

`mlx-swift` ships its compiled Metal shaders as `default.metallib` inside a
SwiftPM resource bundle named `mlx-swift_Cmlx.bundle`. At runtime MLX finds it
via `Bundle.module`. Two things can break it in a distributed app:

1. **Location** — the bundle must end up where `Bundle.module` looks
   (`.app/Contents/Resources/mlx-swift_Cmlx.bundle`).
2. **Signing** — under hardened runtime + notarization, the `.metallib`
   (Mach-O code) and its `.bundle` must be **code-signed**.
   `build_distribution.sh` today copies `*.bundle` and `*.metallib` into
   `Contents/Resources/` **but never signs the nested `.bundle`** (it signs
   only `Frameworks/*` and the outer app, with no `--deep`). That is the most
   likely culprit.

## How to run

```bash
cd mlx-spike

# Test A — baseline: does MLX work at all from the build dir?
swift run mlxspike
#   Expect: "✅ SUCCESS — metallib loaded ..." (bundle is in .build, easy case)

# Test B — the real test: does it load from a signed .app bundle?
./bundle-and-sign.sh
#   This assembles MLXSpike.app exactly like PUSH (copies *.bundle into
#   Contents/Resources), signs nested code first, then runs the binary
#   from inside the bundle.
```

Compare A vs B:
- **A passes, B fails** → it's a bundling/signing problem in the `.app` layout
  (the PUSH blocker). Use the ranked fixes below.
- **Both pass** → bundling is fine; the original blocker may have been a stale
  mlx-swift version. Proceed to wire MLX into PUSH.
- **A fails** → MLX/Metal isn't resolving even in dev; check the diagnostic
  lines the spike prints (which paths it searched, whether the bundle/metallib
  exist) and the mlx-swift version.

## Ranked candidate fixes (apply in Test B until it passes)

1. **Sign the nested bundle + metallib** (most likely). `bundle-and-sign.sh`
   already does this; port the same two `codesign` loops into
   `build_distribution.sh` *before* the final app signing:
   ```bash
   find "$APP_DIR/Contents/Resources" -name "*.metallib" -print0 | while IFS= read -r -d '' m; do
       codesign --force --options runtime --sign "$DEVELOPER_ID" "$m"; done
   find "$APP_DIR/Contents/Resources" -name "*.bundle" -print0 | while IFS= read -r -d '' nb; do
       codesign --force --options runtime --sign "$DEVELOPER_ID" "$nb"; done
   ```
2. **Verify the loose `*.metallib` copy isn't shadowing the bundle.** Lines
   74–78 of `build_distribution.sh` copy bare `default.metallib` into
   `Resources/`. MLX wants it *inside* `mlx-swift_Cmlx.bundle/`, not loose.
   The loose copy is for ggml/llama and is harmless, but confirm both exist
   and MLX reads the bundled one (the spike prints which it finds).
3. **Fallback — adjacent copy.** If `Bundle.module` still can't resolve it in
   the `.app`, also copy `mlx-swift_Cmlx.bundle` next to the executable in
   `Contents/MacOS/`. SwiftPM's `Bundle.module` checks both the executable's
   dir and the main bundle's resources.
4. **Translocation.** If it works in place but fails after moving to
   /Applications, that's Gatekeeper path translocation — a proper Developer ID
   signature + notarization (not ad-hoc) resolves it. Re-test with
   `SIGN_ID="Developer ID Application: ..." ./bundle-and-sign.sh`.

## Notes / caveats
- I could not compile this on Linux. If an MLX Swift API name differs in the
  installed version (e.g. `MLXArray`, `eval`, `sum()`), adjust `main.swift` —
  the goal is just "run one GPU op."
- `mlx-swift` is pinned to `branch: "main"`; pin a version tag once verified.
- Ad-hoc signing (`-`) is enough to test loading locally; only a real Developer
  ID + notarization tests the Gatekeeper/translocation path (fix #4).

## Once Test B passes
Report which fix worked. Then the PUSH integration is: add the MLX dependency +
chosen ASR package (`VincentGourbin/gemma-4-swift-mlx` for Gemma audio, or
`soniqo/speech-swift` for Qwen3-ASR), a new `GemmaEngine`/`Qwen3Engine` actor
mirroring `ParakeetEngine`, a new `WhisperModel` case + routing, and the same
sign-nested-bundles step in `build_distribution.sh`.
