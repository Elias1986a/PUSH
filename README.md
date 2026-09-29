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
- **Fixes itself as you speak.** "The red car, I mean the blue car" pastes *the blue car*. On by default; one switch turns it off.
- **Cleans up as it goes.** Drops "um" and "uh", writes times, money, percentages and spoken quotes the way you would type them, and closes a question the model left open.
- **Lays text out when you ask.** Say "new line", "new paragraph" or "bullet point" and it breaks the line or starts a list item.
- **California mode.** An optional switch that removes casual "like" — "it was like really good" pastes *it was really good* — while keeping "I like it", "looks like rain" and "like I said".
- **Personal dictionary.** Teach it names and jargon it keeps mishearing — globally, or only in context.
- **Live pill.** A floating capsule shows it is listening; Parakeet Streaming draws the words as you say them.
- **Menu bar only.** No dock icon, no window. iCloud syncs your dictionary across Macs; Sparkle handles updates.

## Models

All run on-device. Parakeet Ultra is the default.

| Model | Download | Notes |
|---|---|---|
| **Parakeet Ultra** ⭐ | ~600 MB | Fastest and most accurate. English plus the Latin-script European languages, detected automatically. Transcribes on release. |
| Parakeet Unified | ~600 MB | English only. Transcribes on release. |
| Parakeet Streaming | ~600 MB | English. Transcribes while you speak — long takes land instantly. |
| Nemotron Multilingual | ~600 MB | Every language Ultra doesn't cover — Chinese, Japanese, Arabic, Hindi, Russian, Greek and more. You pick the language. |

Whisper and Moonshine were removed in v7.0.0, Parakeet TDT v2 in 8.0.5, Apple
Speech in 8.2.0. The runs below are why.

---

## Benchmark — 29 September 2026

Every run reads the same passage. It lives in
[`compare/Sources/compare/BenchmarkScript.swift`](compare/Sources/compare/BenchmarkScript.swift)
and is on screen in the comparison tool while you record, so one run can be
compared against the next instead of against a different sentence.

> Let's move the Q3 review to Tuesday, March 3rd at 4:30 PM — Larry, Priya and
> Joe are all in, which puts us at 37% of the $5 million target. Um, latency
> came back at 15.2 seconds, I mean 1.52 seconds, so ask the Zürich team to
> re-run it. Priya said, quote, ship it anyway, end quote. Can you confirm
> before Friday?

**Three readings, 23–26 seconds each. Median seconds from release to transcript.**

| PUSH · Parakeet Ultra | PUSH · Parakeet Unified | Wispr Flow (cloud) |
|:---:|:---:|:---:|
| **0.17 s** | **0.15 s** | **0.79 s** |
| 147× realtime | 150× realtime | 31× realtime |
| on device | on device | + 0.13 s network |

PUSH's default engine finished the passage **4.6× faster than Wispr Flow's
server-side processing**, **5.4× faster** once their network round trip is
counted. Unified is a hair quicker (5.2× / 6.1×) but English-only; Ultra also
handles the European languages. Multiples are against processing time, and
Wispr's realtime figure excludes their network, exactly as the on-device
engines have no network to exclude. Parakeet Streaming measured 0.45 s, but
it transcribes while you talk, so in use most of that is done before you let
go. macOS's built-in recogniser took 0.30 s and was the least accurate of all,
which is why PUSH no longer offers it.

### Accuracy

The passage is built out of the things these engines demonstrably disagree
about, so a run produces this table and not just a stopwatch. PUSH's column is
what it pastes with default settings.

| The script asks for | PUSH · Parakeet Ultra | Wispr Flow |
|---|---|---|
| `$5 million`, spoken "five million dollars" | `$5 million` **in the model's own output**, 3/3 | `five million dollar` → `$5 million` (their server) |
| `4:30 PM` | `4.30 p.m.` → `4:30 p.m.` (PUSH's formatter) | `4:30 PM` |
| "15.2 seconds, I mean 1.52 seconds" | `1.52 seconds`, 3/3 | `1.52 seconds`, 3/3 |
| "Um, latency…" | filler removed | filler removed |
| "quote, ship it anyway, end quote" | `said, "Ship it anyways."` | `said, "Ship it anyways."` |
| `Zürich` | `Zurich` | `Zurich` → `Zürich` |
| `37%`, `Q3`, `March 3rd`, `?` | all correct | all correct |

Ultra misheard one phrase once ("So asked the Zurich team"), and never
recovers the umlaut in `Zürich`, which Wispr's server-side pass does.

Both resolve the spoken correction to `1.52 seconds`. The difference is that
Wispr gives you no way to turn it off; PUSH does (Settings ▸ Text), because
it is the only step that deletes words you actually said.

<details>
<summary>Earlier script — the same passage without the quotation, three runs, with macOS's built-in recogniser</summary>

**Three readings, 20–22 seconds each. Median seconds to transcript.**

| PUSH · Parakeet Ultra | Apple Speech (macOS built-in) | Wispr Flow (cloud) |
|:---:|:---:|:---:|
| **0.14 s** | **0.28 s** | **0.66 s** |
| 142× realtime | 76× realtime | 32× realtime |
| on device | on device | + 0.13 s network |

PUSH's default engine finished the passage **4.7× faster than Wispr Flow's
server-side processing**, **5.6× faster** once their network round trip is
counted, and **2× faster** than Apple's built-in recogniser. Multiples are
against processing time; Wispr's realtime figure excludes their network,
exactly as the on-device engines have no network to exclude.

Medians of three, not a best-of: Ultra ran 0.14 / 0.15 / 0.14 s and Apple 0.28 /
0.29 / 0.26 s, while Wispr came back 0.66 / 1.04 / 0.66 s — the cloud is the
only one of the three whose worst run was 1.6× its best.

### Accuracy

The passage is built out of the things these engines demonstrably disagree
about, so a run produces this table and not just a stopwatch.

| The script asks for | Parakeet Ultra | Apple Speech | Wispr Flow |
|---|---|---|---|
| `$5 million`, spoken "five million dollars" | `$5 million` **in raw output**, 3/3 | `$5000000` → `$5,000,000` (PUSH's formatter) | `five million dollar` → `$5 million` (their server) |
| `4:30 PM` | `4.30 p.m.` → `4:30 p.m.` | `4.30 p.m.` → `4:30 p.m.` | `4:30 PM` in raw |
| `1.52 seconds` | correct 3/3 | `one. 52 seconds` 3/3 ✗ | correct 3/3 |
| `Zürich` | `Zurich` 2/3, `Zurek` once | `Zurich` | `Zurich` → `Zürich` |
| `37%`, `Q3`, `March 3rd`, `?` | all correct | dropped "Priya" once | all correct |

Ultra is the only engine that produced `$5 million` on device, first try, with
nothing left to clean up — the other two reach the same string only through
post-processing, one of them by sending the audio to a server. It never
recovers the umlaut in `Zürich`, which Wispr's server-side pass does.

</details>

<details>
<summary>Archived run — 18 August 2026, including the engines PUSH has since dropped</summary>

A different sample (8.3 s) and a different default engine — Parakeet Unified,
before Ultra existed. Kept because it is the measurement that retired Whisper
and Moonshine. Not comparable row-for-row with the run above.

Times are release → transcript on one Apple silicon Mac, model loading excluded.

| Engine | Transcribe | × realtime |
|---|---|---|
| **Parakeet Unified** | **0.061 s** | **136×** |
| Parakeet TDT v2 | 0.074 s | 112× |
| Apple Speech | 0.118 s | 70× |
| Parakeet Streaming | 0.161 s | 52× |
| Wispr Flow (cloud) | 0.492 s + 0.095 s network | 17× |
| Whisper Small | 0.947 s | 8.8× |
| Whisper Large v3 Turbo | 1.106 s | 7.5× |
| Moonshine Tiny | failed to load | — |

Parakeet Unified was **18× faster than Whisper Large v3 Turbo** on that machine.
That gap is why Whisper and Moonshine came out in v7.0.0.

</details>

> One reading, one machine, one day — not an average over a corpus. Parakeet
> Unified, Streaming and Nemotron Multilingual were not on disk for this run and
> so are absent from it. Fixing the script makes future runs comparable to this
> one; it does not make this one comparable to the 18 August figures below, which
> were a different sentence of a different length. Every engine here keeps
> shipping new versions, so if you re-run this today you should expect different
> numbers — that is the point of shipping the tool. It lives in `compare/`: build
> it with `./compare/build_compare.sh`, read the passage, measure your own
> hardware.

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

Swift · SwiftUI · [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet + Silero VAD on CoreML/ANE) · Sparkle

## Contributing

[Issues](https://github.com/Elias1986a/PUSH/issues) and pull requests welcome. MIT licensed.
