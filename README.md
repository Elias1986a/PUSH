# PUSH

**Offline voice-to-text for macOS.** Hold a key, speak, release — the text lands
in whatever you were typing in. Nothing leaves your Mac.

**[Download the latest release](https://github.com/Elias1986a/PUSH/releases/latest)** · macOS 15+ · Apple silicon

---

## What it does

- **Hold to talk.** Hold Right Option (or any key you pick), speak, release. Esc cancels.
- **Or say a wake word.** Hands-free start, with voice activity detection ending the take on silence.
- **Lands anywhere.** Text is inserted into the focused field of any app.
- **Fully offline.** Speech recognition runs on the Neural Engine. No accounts, no API keys, no network.
- **Fixes itself as you speak.** "The red car, I mean the blue car" pastes *the blue car*. On by default; one switch turns it off.
- **Cleans up as it goes.** Drops "um" and "uh", writes times, money, percentages and spoken quotes the way you would type them, and closes a question the model left open.
- **Lays text out when you ask.** Say "new line", "new paragraph" or "bullet point" and it breaks the line or starts a list item; "number one … number two …" makes a numbered list.
- **California mode.** An optional switch that removes casual "like" — "it was like really good" pastes *it was really good* — while keeping "I like it", "looks like rain" and "like I said".
- **Personal dictionary.** Teach it names and jargon it keeps mishearing — globally, or only in context.
- **Live pill.** A floating capsule shows it is listening; Parakeet Streaming draws the words as you say them.
- **Menu bar only.** No dock icon, no window. iCloud syncs your dictionary across Macs; Sparkle handles updates.

## Models

All run on-device. The default follows your Mac's language: Parakeet Streaming
on an English Mac, Parakeet Ultra anywhere else.

| Model | Download | Notes |
|---|---|---|
| **Parakeet Streaming** | ~600 MB | English only. Shows your words as you speak and transcribes while you talk. Default on an English Mac. |
| **Parakeet Ultra** | ~600 MB | English plus the Latin-script European languages, detected automatically. Transcribes each sentence as you finish it. Default everywhere else. |
| Nemotron Multilingual | ~600 MB | Every language Ultra doesn't cover — Chinese, Japanese, Arabic, Hindi, Russian, Greek and more. You pick the language. |

Whisper and Moonshine were removed in v7.0.0, Parakeet TDT v2 in 8.0.5, Apple
Speech in 8.2.0, Parakeet Unified in 8.2.5. The runs below are why.

---

## Benchmark — 30 September 2026

Every run reads the same passage. It lives in
[`compare/Sources/compare/BenchmarkScript.swift`](compare/Sources/compare/BenchmarkScript.swift)
and is on screen in the comparison tool while you record, so one run can be
compared against the next instead of against a different sentence.

> Let's move the Q3 planning review to Tuesday, March 3rd at 4:30 PM, since
> that's like the only slot that works for the Zürich office. Um, we've spent
> 37% of the $5 million budget, and the new build loads in 15.2 seconds, I mean
> 1.52 seconds. Everyone who tried it said, quote, it feels like a real
> improvement, end quote. New paragraph. Could you like send the final numbers
> before Friday?

**13 readings, 23–29 seconds each, Mac mini M4. Median seconds from releasing
the key to text.**

| PUSH · Parakeet Streaming | PUSH · Parakeet Ultra | Wispr Flow (cloud) |
|:---:|:---:|:---:|
| **0.02 s** | **0.04 s** | **0.74 s** |
| on device | on device | + 0.13 s network |

PUSH transcribes while you talk, so letting go leaves only the last moment to
decode. That makes it about **20× faster than Wispr Flow** including their
network, 17× against their processing alone. On what the passage tests —
money, the "I mean" correction, the spoken quote, the paragraph break, casual
"like" — every engine was right on every reading; Wispr Flow restored the
umlaut in Zürich 5 times in 12, and PUSH never does. Parakeet Unified tied
Ultra on accuracy at 0.05 s, English only, which is why it went. The full
table is on the website's "How we measured" page.

## Setup

1. Download the DMG from [Releases](https://github.com/Elias1986a/PUSH/releases/latest), drag PUSH to Applications, launch it. It is signed and notarized.
2. Allow **Microphone** when asked.
3. Allow **Accessibility** (System Settings → Privacy & Security → Accessibility) — needed for the global hotkey and for inserting text.
4. The welcome window downloads the recommended model (Settings → Models to change it).
5. Click into any text field, hold Right Option, talk.

**Build from source:** `swift build` · `swift run` · `swift test`.
Release builds go through `./build_distribution.sh` (see [DISTRIBUTION.md](DISTRIBUTION.md)).

## Privacy

Audio is recorded only while the key is held (or after the wake word) and is
transcribed on this Mac. No audio, no transcripts, and no telemetry are ever
sent anywhere. Models live in `~/Library/Application Support/PUSH/models/` and
can be deleted any time.

## Tech

Swift · SwiftUI · [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet + Silero VAD on CoreML/ANE) · Sparkle

## License

Proprietary. See [LICENSE](LICENSE) and the [EULA](legal/EULA.md). Versions up
to 8.2.2 were MIT-licensed and remain so. Open-source components and speech
models are credited in [Third-party notices](legal/THIRD_PARTY_NOTICES.md).
