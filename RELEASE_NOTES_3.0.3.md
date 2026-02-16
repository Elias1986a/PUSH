# PUSH v3.0.3 Release Notes

## Changes

- **Eliminated cold start on first transcription** — Model warmup (Metal shader compilation) now runs as part of the download step. The spinner stays active until the model is fully ready, so the first transcription is instant.
- **Fixed Whisper silence hallucinations** — Holding the button without speaking no longer produces "Thank you" or other phantom text. Common hallucination phrases are now filtered out.
- **Capitalize pronoun "I"** — Standalone "i" is now always capitalized to "I".
- **Double space after periods** — Sentences are followed by two spaces after `.` `?` `!` for cleaner formatting.

## Version Bumps Needed

- `PUSH/Info.plist`: CFBundleShortVersionString → `3.0.3`, CFBundleVersion → `17`
- `PUSH/Views/SettingsView.swift`: AboutView version text → `3.0.3`
- `build_distribution.sh`: ZIP_NAME/DMG_NAME → `PUSH-v3.0.3`

## Build & Release

```bash
./build_distribution.sh
```
