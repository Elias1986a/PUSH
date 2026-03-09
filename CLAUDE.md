# CLAUDE.md — PUSH

## Project Overview
macOS Swift app — push notification management or local AI/LLM integration tool. Swift Package Manager project.

## Tech Stack
- Swift (Package.swift, not Xcode project)
- SPM Dependencies: SwiftLlama, WhisperKit, Moonshine, LaunchAtLogin
- Firebase integration
- LLM inference via llama.cpp bindings

## Commands
- `swift build` — build the project
- `swift run` — run the app
- Build scripts: `build_distribution.sh`, `build_xcode_project.sh`

## Project Structure
- `Sources/` — Swift source code
- `docs/` — Documentation
- `ICON/` — App icon assets
- `dist-build/` — Distribution build output

## Key Notes
- Uses local LLM inference (SwiftLlama + llama.cpp)
- Uses WhisperKit for speech-to-text
- LaunchAtLogin for startup behavior
- Has distribution/signing scripts for macOS distribution
