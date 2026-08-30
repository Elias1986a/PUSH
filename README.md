# PUSH

**Offline voice-to-text for macOS.** Hold a key, speak, release — the text lands
in whatever you were typing in. Nothing leaves your Mac.

**[Download the latest release](https://github.com/Elias1986a/PUSH/releases/latest)** · macOS 15+ · Apple silicon · MIT

---

## What it does

- **Hold to talk.** Hold Right Option (or any key you pick), speak, release. Esc cancels.
- **Or say a wake word.** Hands-free start, with voice activity detection ending the take on silence.
- **Lands anywhere.** Text is inserted into the focused field of any app.
- **Fully offline.** Speech recognition runs on the Neural Engine. No accounts, no API keys, no network.
- **Fixes itself as you speak.** "The red car, I mean the blue car" pastes *the blue car*.
- **Personal dictionary.** Teach it names and jargon it keeps mishearing — globally, or only in context.
- **Live pill.** A floating capsule shows it is listening; Parakeet Streaming draws the words as you say them.
- **Menu bar only.** No dock icon, no window. iCloud syncs your dictionary across Macs; Sparkle handles updates.

## Models

All four run on-device. Parakeet Unified is the default.

| Model | Download | Notes |
|---|---|---|
| **Parakeet Unified** ⭐ | ~600 MB | Most accurate and fastest. Transcribes on release. |
| Parakeet Streaming | ~600 MB | Transcribes while you speak — long takes land instantly. |
| Parakeet TDT v2 | ~400 MB | Older English model, smaller download. |
| Apple Speech | — | Built into macOS 26. Nothing to download. |

Whisper and Moonshine were removed in v7.0.0. The numbers below are why.

---

## Benchmark — measured 18 August 2026

**8.3 seconds of speech. Seconds to transcript, per engine.**

| PUSH · Parakeet Unified | PUSH · Parakeet TDT v2 | PUSH · Parakeet Streaming | Wispr Flow (cloud) |
|:---:|:---:|:---:|:---:|
| **0.061 s** | **0.074 s** | **0.161 s** | **0.492 s** |
| 136× realtime | 112× realtime | 52× realtime | 17× realtime |
| on device | on device | on device | + 0.095 s network |

PUSH's default engine finished the same utterance **8× faster than Wispr Flow's
server-side processing** — before their round trip is counted at all.

<details>
<summary>Every engine measured that day, including the ones PUSH dropped</summary>

Times are release → transcript on one Apple silicon Mac, model loading excluded.

| Engine | Transcribe | × realtime |
|---|---|---|
| **Parakeet Unified** | **0.061 s** | **136×** |
| Parakeet TDT v2 | 0.074 s | 112× |
| Apple Speech | 0.118 s | 70× |
| Parakeet Streaming | 0.161 s | 52× |
| Wispr Flow (cloud) | 0.492 s + 0.095 s network | 17× |
| Whisper Small * | 0.947 s | 8.8× |
| Whisper Large v3 Turbo * | 1.106 s | 7.5× |
| Moonshine Tiny | failed to load | — |

Parakeet Unified is **18× faster than Whisper Large v3 Turbo** on the same
machine. That gap is why Whisper and Moonshine came out in v7.0.0.

</details>

> These are the figures from that date, on that machine, on that one recording.
> Every engine here keeps shipping new versions; if you re-run this today you
> should expect different numbers. The comparison tool that produced them lives
> in `compare/` — build it with `./compare/build_compare.sh` and measure your
> own hardware.

<sub>\* **How the Whisper numbers were taken.** Every engine transcribed the
*same* recorded audio buffer, one at a time — never in parallel, since two
models competing for the Neural Engine would corrupt each other's timings.
Whisper ran through WhisperKit's CoreML builds on the Neural Engine, the same
path PUSH itself used when it shipped Whisper, not a CPU or `whisper.cpp`
fallback. Each model was loaded **and warmed up before the clock started**, so
Whisper Large v3 Turbo's ~2-minute first-run CoreML compile is excluded rather
than charged against it — the timing is a warm, steady-state transcription, the
best case for Whisper. Output went through the same post-processing for all
engines. Moonshine Tiny is listed as a failure, not a slow result: its weights
only ever existed in the upstream package's test resources and never shipped,
so it could not load at all.</sub>

---

## Setup

1. Download the DMG from [Releases](https://github.com/Elias1986a/PUSH/releases/latest), drag PUSH to Applications, launch it. It is signed and notarized.
2. Allow **Microphone** when asked.
3. Allow **Accessibility** (System Settings → Privacy & Security → Accessibility) — needed for the global hotkey and for inserting text.
4. Menu bar icon → Settings → Models → download Parakeet Unified.
5. Click into any text field, hold Right Option, talk.

**Build from source:** `swift build` · `swift run` · `swift test`.
Release builds go through `./build_distribution.sh` (see [DISTRIBUTION.md](DISTRIBUTION.md)).

## Privacy

Audio is recorded only while the key is held (or after the wake word) and is
transcribed on this Mac. No audio, no transcripts, and no telemetry are ever
sent anywhere. Models live in `~/Library/Application Support/PUSH/models/` and
can be deleted any time.

## Tech

Swift · SwiftUI · [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet + Silero VAD on CoreML/ANE) · Apple SpeechAnalyzer · Sparkle

## Contributing

[Issues](https://github.com/Elias1986a/PUSH/issues) and pull requests welcome. MIT licensed.
