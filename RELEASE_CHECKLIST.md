# Release checklist — PUSH v4.1.5 (Gemma audio engine)

Version is already bumped to **4.1.5 / build 32** (`PUSH/Info.plist`), and the
MLX nested-bundle signing is in `build_distribution.sh`. Run all of this **on
the Mac** (Apple Silicon), with the `claude/gemma-audio-engine` branch checked out.

This release adds the **Gemma 4 E2B** engine (MLX). Because it ships a new
heavy dependency to every existing user via Sparkle auto-update, do NOT skip the
notarized `/Applications` gate.

## Gate 1 — Functional (must pass before building for release)
- [x] `swift build` succeeds with the Gemma engine wired in.
- [ ] **Runtime verify**: in the real app, select "Gemma 4 E2B — Multilingual
      (beta)", let it download (~3.6 GB), and confirm a live mic dictation
      produces correct text end-to-end. (Mac runtime menu → option 2.)
- [ ] Sanity-check the existing engines (Parakeet/Whisper) still transcribe —
      we changed shared enums/switches, so confirm nothing regressed.

## Gate 2 — Distribution (the MLX risk — never tested before)
Run the real distribution build, which signs + notarizes:
```
export DEVELOPER_DIR="/Volumes/Part 2/Applications/Xcode-beta.app/Contents/Developer"
./build_distribution.sh
```
- [ ] Notarization succeeds (the script staples + rebuilds the ZIP).
- [ ] **Copy `PUSH.app` to `/Applications`, launch it from there**, and confirm
      the Gemma model still loads (this is spike fix #4 — proves MLX's
      `default.metallib` survives notarization + Gatekeeper translocation).
      If Gemma fails to load here but worked in dev, the nested-bundle signing
      needs attention before shipping.

## Gate 3 — Publish (this is what reaches users; do last)
- [ ] Confirm `appcast.xml` was regenerated with `sparkle:shortVersionString`
      = 4.1.5 and a valid `edSignature`.
- [ ] Create the GitHub release (tag MUST be `v4.1.5` to match the appcast URL):
      ```
      gh release create v4.1.5 --title "PUSH v4.1.5" --generate-notes \
        PUSH-v4.1.5.zip PUSH-v4.1.5.dmg
      ```
- [ ] Publish the appcast to the branch the app's `SUFeedURL` points at
      (check `PUSH/Info.plist` — usually `main`):
      ```
      git add appcast.xml && git commit -m "Release v4.1.5" && git push
      ```
- [ ] Merge `claude/gemma-audio-engine` → `main` (PR #7) so the shipped code
      matches the tag.

## Rollback
If a problem surfaces post-publish, revert the `appcast.xml` commit (or point
its enclosure back at the v4.1.4 ZIP) and push — Sparkle clients stop being
offered 4.1.5. The bad release tag can be deleted separately.

## Release notes draft
> **v4.1.5**
> - New (beta): **Gemma 4 E2B** on-device transcription engine — multilingual,
>   runs on the GPU via MLX. Opt in under Settings → Speech Model. ~3.6 GB
>   download; 30 s max per dictation.
> - Existing Whisper / Moonshine / Parakeet engines unchanged.
