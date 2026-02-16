# PUSH v3.0.3 Release Notes

## Changes

- **Eliminated cold start on first transcription** — Model warmup (Metal shader compilation) now runs as part of the download step. The spinner stays active until the model is fully ready, so the first transcription is instant.
- **Fixed Whisper silence hallucinations** — Holding the button without speaking no longer produces "Thank you" or other phantom text.
- **Smart question marks** — Sentences starting with question words (who, what, how, is, can, etc.) that end with a period are auto-corrected to end with a question mark.
- **Stutter removal** — Duplicate consecutive words ("the the", "I I") are collapsed to one.
- **Filler word cleanup** — "um" and "uh" are removed. "like" is only removed when it's clearly filler (", like,"), preserved in real usage ("I like pizza").
- **Capitalize pronoun "I"** — Standalone "i" is now always capitalized.
- **Double space after periods** — Two spaces after `.` `?` `!`

## Version Bumps Needed

- `PUSH/Info.plist`: CFBundleShortVersionString → `3.0.3`, CFBundleVersion → `17`
- `PUSH/Views/SettingsView.swift`: AboutView version text → `3.0.3`
- `build_distribution.sh`: ZIP_NAME/DMG_NAME → `PUSH-v3.0.3`

## Build & Release

```bash
./build_distribution.sh
```
