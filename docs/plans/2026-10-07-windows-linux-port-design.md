# Windows + Linux Port — Design (v2)

**Status:** planned, not committed. Written 2026-10-07 against v8.2.7. Supersedes
`2026-08-29-windows-port-design.md`. That document is still accurate on the
Windows traps and kept as the record of the first analysis. Its engine plan,
stack and estimates no longer hold.

## Goal

The same product on Windows and Linux: hold a key, speak, and the text lands in
the focused field, all on-device. Windows is the commercial target, a market
roughly ten times the Mac's. Linux follows once Windows sells. Because the core
is shared, it costs only its own input and windowing layer.

**Scope rule: draw a line, as the Mac does.** The Mac app is Apple Silicon and
macOS 15 only. Windows gets the same kind of cutoff (Windows 11, 16 GB, a
measured speed check) and a v1 that matches what a non-English Mac gets today:
Parakeet Ultra, no live preview. Everything else is a follow-up that has to earn
its place. The Mac app is not part of this
plan. It stays Swift on CoreML/ANE, which is where its speed comes from.

## What changed since the August plan

| August assumption | Now (v8.2.7) | Consequence |
|---|---|---|
| Default is Parakeet Unified (CoreML-only); Windows "cannot inherit" it | Unified was removed in 8.2.5. The default is **Streaming** on English Macs and **Ultra** elsewhere | Ultra is moondream's post-training of **TDT v3**. It keeps v3's architecture and tokenizer and is CC-BY-4.0. TDT v3 already has ONNX exports that run well on CPU (Handy ships it). The default can now cross platforms. |
| Phase 0 candidates: TDT v2, Moonshine, whisper-small | TDT v2 was removed in 8.0.5 | Replace the candidates with the actual lineup (below) |
| Streaming partials cut from v1 | Streaming is the English default, but **the live preview is off by default** (`showLivePreview = false`). Streaming's case as default is latency after release (0.02 s vs Ultra's 0.04 s) | Ultra with LiveDecoder covers release latency on CPU. Streaming and the preview stay **v1.1**, gated on a CPU engine passing |
| No multilingual | Ultra auto-detects European languages. Nemotron 3.5 Multilingual covers the rest, with a per-engine language picker | Needs a CPU Nemotron and a non-Apple language ID |
| Text pipeline: 928 lines | **~1,960 lines across 8 files.** Self-corrections, California mode, quotes, numbers, filler "like", plus `ScriptAligner` (454) | A second implementation would cost twice what August assumed, and it would drift. **Share it instead of porting** (see Stack) |
| Licensing is net-new | `PolarLicense` exists: $22 for 3 Macs, $10 per extra Mac. Keys are in the Keychain and the machine identity comes from IOKit | The HTTP client ports as it is. Only the key storage and the device ID are per-OS |
| Windows only, so WPF | Linux is now in scope | **WPF is out.** Two native shells would double the UI work |
| — | New since then: LiveDecoder (sentence-aligned windows), teleprompter, media ducking, start sounds, ModelLoader stall watchdog | LiveDecoder matters *more* on CPU, and it is what makes Ultra-only v1 viable. The teleprompter waits for later |

The app is now ~15,500 lines (10,800 app, 4,700 `PUSHCore`) with ~4,500 lines of
tests. The share that is platform-neutral has grown, which is what makes sharing
code worth doing now.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Platforms | **Windows 11 only**, x64 + arm64. Linux after Windows v1 ships (x64, Ubuntu LTS + Fedora; X11, KDE and wlroots first-class; GNOME reduced) | Windows 10 left support in October 2025. Windows 11's own CPU list (~2018+) already removes most of the old-hardware long tail. Linux is cheap once the core is shared, but it is not worth paying for up front |
| Hardware floor | Windows 11, 16 GB RAM, CPU-only, **plus a speed check in onboarding**: transcribe a bundled 5 s clip, and if it takes over ~700 ms, say "this PC is too slow for PUSH" before purchase | A measured gate beats a CPU list: the same chip runs at very different speeds across laptop cooling and power plans. Copilot+ NPUs are *not* the cutoff: three vendors and three toolchains is a wider matrix than CPUs. NPU is a later speed tier through the EP interface |
| Core + shell | **Rust core + Tauri 2 shell** | One UI for both OSes. A crate exists for every interop piece (ort, cpal, ashpd, wayland-client, windows-rs). Handy is the precedent: the same product category on the same stack, shipping on all three OSes with Parakeet v3 on CPU. Runner-up: C#/Avalonia |
| Text pipeline | **Compile the Swift `PUSHCore` text rules for Windows/Linux as a C library.** Fall back to a Rust port + golden corpus only if the Phase 0 spike fails | The rules then live in one place and change once. The existing 4,500 lines of tests run on Windows/Linux CI as the drift check |
| ASR runtime | ONNX Runtime (via `ort`), int8 or int4, CPU EP. sherpa-onnx where it already supports the model | Same reasoning as August. The EP seam later admits Windows ML (which downloads vendor NPU EPs), DirectML or CUDA |
| v1 scope | Hotkey → record → VAD → **Ultra** (with LiveDecoder) → text pipeline → paste. Pill (recording state, no preview). Dictionary + context gate. Media ducking. Licensing | This is what a non-English Mac runs today, and Ultra covers English plus the Latin-script European languages. Live preview, Nemotron, wake word, teleprompter and sync wait. See "Cut from v1" |
| Elevated apps (Windows) | Detect and explain, as in August | Unchanged |

## Engine lineup off the Mac

The Mac rule still holds: **the bake-off decides, not the leaderboard.** v1
ships one engine, Ultra. The other two slots are v1.1, and the bake-off
measures them now so that decision is ready when it comes:

| Mac slot | Mac engine (CoreML/ANE) | CPU candidate | Status of the ONNX export |
|---|---|---|---|
| Ultra (batch, European auto-detect) | Parakeet Ultra | **Ultra exported to ONNX int8**, falling back to stock TDT v3 int8 | TDT v3: several exist (sherpa-onnx int8, istupakov/onnx-asr). Ultra: same architecture, but **we must export it ourselves**. That needs the NeMo checkpoint to be released (open question 1) |
| Streaming (English, partials) | Parakeet Unified streaming | **Nemotron Speech Streaming EN 0.6B**, int8 | Supported by sherpa-onnx (needs ≥ 1.13.4 to decode correctly). OpenWhispr ships it on CPU. No ONNX export of Parakeet Unified is known |
| Multilingual (picked language) | Nemotron 3.5 Multilingual | **Nemotron 3.5 ASR Streaming 0.6B** ONNX | Community exports exist (onnx-community int4, codavidgarcia fp16 + a reference engine). sherpa-onnx does not yet take its `prompt_index` input (issue #3664), so drive it with `ort` directly or contribute that support |

Nemotron 3.5 might cover both streaming slots. It is the English model's
multilingual extension with a language prompt. If its English WER on our corpus
matches Nemotron EN, ship one streaming engine instead of two. Phase 0 decides
this.

**LiveDecoder ports with Ultra, in v1.** Sentence-aligned windows decoded while
the user speaks are what keep Ultra's latency after release flat on long
dictation. On a CPU the gap is bigger than on the ANE, so this is a core
feature, not an optimisation. The logic is pure (`SentenceAlignedWindows`,
`LiveDecoder`) and can go in the shared Swift library if the spike shows it fits.

**Silero VAD:** August said to use "the same `.onnx` file the Mac ships". That
was wrong. The Mac loads Silero as CoreML through FluidAudio. Use Silero's
official ONNX release.

**Licences:** Ultra and TDT v3 are CC-BY-4.0, so attribution goes in the About
pane and the licences file. Nemotron is under the NVIDIA Open Model License,
which allows commercial use per the model card. Read the text before shipping.

## Architecture

```
┌────────────────────────── Tauri 2 shell (TS UI) ──────────────────────────┐
│ tray · onboarding · settings · model downloads · licence · pill window    │
└──────────────────────────────┬────────────────────────────────────────────┘
                               │ commands / events
┌──────────────────────────────▼────────────────────────────────────────────┐
│ push-core (Rust)                                                          │
│  input/      hotkey + injection, one impl per OS/session (below)          │
│  audio/      cpal capture → 16 kHz mono f32, device list, ducking          │
│  vad/        Silero ONNX                                                   │
│  asr/        AsrEngine trait: Ultra (batch+LiveDecoder); Nemotron in v1.1 │
│  models/     ModelLoader port: generation-ordered activation, explicit     │
│              timeouts, stall watchdog, launch never downloads              │
│  license/    Polar client, device ID, key in OS credential store          │
└──────────────────────────────┬────────────────────────────────────────────┘
                               │ C ABI: push_process(text, opts_json) → text
┌──────────────────────────────▼────────────────────────────────────────────┐
│ libpushtext (Swift, built from PUSHCore's text targets)                   │
│  TextProcessing*, CorrectionsStore, ContextGate, TranscriptLanguage,      │
│  ScriptAligner. Platform services injected as callbacks (below)           │
└───────────────────────────────────────────────────────────────────────────┘
```

The data flow mirrors `TranscriptionPipeline`: hook → recorder → VAD → engine →
text → injector. The rules from CLAUDE.md carry over unchanged:
- Only `models/` loads or unloads engines.
- Activations cancel each other rather than wait.
- Every network fetch has a timeout and a watchdog.
- Launch never downloads.
- Transcript text is never logged.

### Sharing the text pipeline

The rules touch Apple-only APIs in only four places:

| Apple API | Used by | Windows / Linux provider |
|---|---|---|
| `NLTagger` `.lexicalClass` | `FillerLike`, `CaliforniaLike` ("like" as filler vs verb/preposition) | A small English POS lexicon shipped with the library. The existing tests decide whether it is good enough |
| `NLLanguageRecognizer` | `TranscriptLanguage` (reads Ultra's language back from its output) | `lingua`/`whatlang` in Rust, passed in as a callback |
| `NSSpellChecker` | `ContextGate` (is this word a real word?) | Windows `ISpellChecker`. Linux Enchant/Hunspell |
| `import NaturalLanguage` in 5 more files | No calls beyond the above | Remove the imports |

Step one is Mac-side work, worth doing anyway. Put these four behind protocols
and move the pure rules into their own `PUSHText` target with no FluidAudio
dependency. Then `swift build` that target on Linux and Windows CI and run the
existing tests there. Any test that fails exposes a corelibs-Foundation
difference to fix once, in the place where both platforms see it.

Cost: Swift runtime DLLs on Windows (tens of MB, small next to a 600 MB model),
a static stdlib on Linux, and a Swift toolchain in Windows CI. The kill condition
is in Phase 0.

## Windows

All five traps from August still hold: the LL hook timeout, UIPI, clipboard
contention, the keylogger signature, and per-monitor DPI. Read them there. The
additions:

**6. Right Alt is AltGr.** The Mac default is Right Option. On German, French,
Polish and most European layouts, Right Alt *is* AltGr and types `@ € { }`.
Holding it to dictate would break typing. **The default on Windows and Linux is
Right Ctrl**, and onboarding warns if the user picks Right Alt on an AltGr
layout.

**7. Clipboard history and cloud clipboard.** Each paste would otherwise land in
Win+V history and sync to the user's other devices: a transcript leak the Mac
does not have. When writing, set `ExcludeClipboardContentFromMonitorProcessing`,
`CanIncludeInClipboardHistory = 0` and `CanUploadToCloudClipboard = 0`. This is
the counterpart of the Mac's `org.nspasteboard.TransientType`.

**8. Media ducking.** Lower the default render endpoint through
`IAudioEndpointVolume` and restore it after, as the Mac does. Windows'
communications ducking is a user setting, so it can't be relied on.

**9. arm64.** Snapdragon X laptops are a real share of new premium Windows
machines. `ort` and Tauri both build for arm64. Ship it from day one, CPU EP
only. The QNN NPU belongs to the later Windows ML tier.

**Distribution:** Azure Trusted Signing, as in August. The installer is the
Tauri NSIS bundle, per-user, no UAC. Updates use `tauri-plugin-updater` against
a signed static feed. That replaces August's Velopack choice, since the shell
now brings its own updater. Submit to AV vendors as a scheduled task.

## Linux

The Linux work is mostly an input and windowing matrix. Audio (cpal over
PipeWire/Pulse), engines and the text pipeline are shared and need no
Linux-specific code.

| Session | Hold-to-talk hotkey | Paste | Pill | Tier |
|---|---|---|---|---|
| X11 (any desktop) | XInput2 raw key events | X selection + XTest Ctrl+V | Override-redirect, input-transparent | **Full** |
| KDE Plasma 6, Wayland | GlobalShortcuts portal (`Activated`/`Deactivated`) | RemoteDesktop portal (one consent prompt) + data-control clipboard | wlr-layer-shell | **Full** |
| wlroots / Hyprland / Sway | Portal, or a compositor binding to `push hold`/`push release` | Virtual-keyboard protocol + data-control clipboard | wlr-layer-shell | **Full** |
| GNOME 48+, Wayland | GlobalShortcuts portal | RemoteDesktop portal (consent; persists on newer portal versions) | **None.** GNOME has no layer-shell, so the state shows in the tray (needs the AppIndicator extension) | **Reduced** |

Unverified and must be measured in Phase L0:
- Does each portal's `Deactivated` fire promptly on key release?
- Can a user bind a modifier-only key (bare Right Ctrl) through the portal?
- Can a background client set the Wayland clipboard on GNOME, and if not, does
  the RemoteDesktop session's clipboard interface cover it?

If key release can't be measured reliably on GNOME, GNOME gets toggle-to-talk
(press to start, press to stop) instead of hold.

**Raw `/dev/input` (evdev/uinput) is opt-in only.** It works everywhere, but it
needs membership in the `input` group, which means reading every keystroke on
the machine. That is the keylogger shape again, so it never becomes the default.

Clipboard managers (Klipper, GPaste) record pastes. Write the
`x-kde-passwordManagerHint: secret` type alongside the text. This is the Linux
counterpart of trap 7.

**Packaging:** .deb + .rpm + AppImage from the Tauri bundler. AppImage
self-updates. Flatpak comes later: its sandbox suits the portal path and blocks
the evdev path, so it should follow the portal work, not lead it. Linux ships as
a public beta at the same price, with the support matrix above on the download
page.

## Licensing across platforms

Polar's licence endpoints are already the desktop-app "customer portal" ones and
carry no secret, so `PolarLicense` ports to Rust as a direct translation. Per OS:

- **Device ID:** Windows `MachineGuid`, Linux `/etc/machine-id`, each hashed
  with an app salt. The Mac uses the IOKit platform UUID.
- **Key storage:** Windows Credential Manager, Linux Secret Service (libsecret).
  The Mac uses the Keychain.
- **Product decision (open question 2):** whether one key covers any OS. The
  recommendation is yes. "$22, 3 devices, any OS" is simpler to explain than
  per-platform SKUs, and Polar already counts activations per key, not per OS.
  It needs the Mac copy changed from "Macs" to "devices" when it launches.

## Cut from v1

- **Live preview and Parakeet Streaming's slot.** Off by default on the Mac, so
  v1 doesn't need it. v1.1 if Nemotron EN (or 3.5) keeps up live on the floor
  box (RTF < 0.5).
- **Nemotron multilingual** (Chinese, Japanese, Arabic, Hindi, Russian, Greek…).
  Ultra already covers English and the European languages. v1.1, alongside the
  preview, since it is the same streaming plumbing.
- **Linux.** It follows once Windows v1 ships. Phase L0 can still run at any
  time, because it is cheap and needs nothing from Windows.
- **Wake word.** Today it runs the active ASR engine on a 1.5 s buffer every
  0.3 s. On the ANE that is cheap. On a laptop CPU it is a constant 600M-param
  load and a battery drain. Revisit it with a dedicated keyword-spotting model
  (sherpa-onnx KWS, openWakeWord), on all platforms.
- **Teleprompter.** `ScriptAligner` comes free in the shared library, but the
  window and session do not. It is a second product.
- **Sync.** `CloudSync` is iCloud key-value storage. Off the Mac, offer dictionary
  export/import as a file instead. Real sync needs a backend and stays out of
  scope.

## Roadmap

As in August, the phases are kill gates, not a march.

| Phase | Work | Effort | Gate |
|---|---|---|---|
| **0a** | **Engine bake-off.** A Rust console harness using `ort` and sherpa-onnx. Ultra-ONNX (or TDT v3) is the v1 contestant. Nemotron EN and 3.5 are measured for v1.1. The same WAV corpus `compare/` uses. Measures WER, latency after release and RTF on two boxes: a 2019 Windows 11 laptop (8th-gen i5, 16 GB) and a Snapdragon X | ~1 wk | **Ultra p50 ≤ 700 ms** from end of speech to text on a 5 s utterance on the 2019 box. If it fails, raise the cutoff (newer CPUs) before cutting the product |
| **0b** | **Swift text spike.** Extract `PUSHText` with the four providers abstracted. Build it on Windows + Linux CI, run the existing tests, call it through the C ABI from a Rust test | ~1 wk | Tests green on all three OSes. If not → port to Rust + golden corpus (+4–5 wk to Phase 2) |
| **1** | **Windows walking skeleton.** Hook thread → WASAPI (cpal) → Silero → Ultra → libpushtext → clipboard paste. Tray icon only | 2–3 wk | Does it type into Chrome, Word, Slack, VS Code, Windows Terminal, Teams? |
| **2** | **Core parity.** LiveDecoder, ModelLoader port (generation, timeouts, watchdog), dictionary/context gate, ducking | 1–2 wk | Ultra-on-Mac behaviour reproduced on the bake-off corpus |
| **3** | **Product surface (Tauri).** Pill (state only), onboarding (mic consent, hotkey with the AltGr warning, **speed check**), settings panes, model download with progress, launch at login | 3–4 wk | — |
| **4** | **Windows distribution.** Trusted Signing, NSIS, updater feed, AV submissions, model mirror (see open question 3) | ~2 wk | Clean install/update/uninstall; no SmartScreen wall |
| **5** | **Licensing.** Rust Polar client, device ID, credential store, store copy | ~1 wk | Activation, offline grace and deactivation, tested against Polar sandbox |

**Windows v1: ~11–14 weeks.** August estimated 12–17 for Windows alone, and the
first draft of this plan 14–19. The Windows 11 cutoff and the Ultra-only v1 take
out the streaming engines, the language routing and the live pill.

**Afterwards, each as its own decision:**

| Follow-up | Work | Effort |
|---|---|---|
| **v1.1 — Streaming** | Nemotron EN or 3.5 behind the `AsrEngine` trait, live preview in the pill (off by default, as on the Mac), multilingual picker | 3–4 wk |
| **L0 — Linux input spike** | One small binary per row of the Linux table, logging press/release timing and attempting a paste. It can run at any time | ~1 wk |
| **L1 — Linux** | The input/window backends L0 justified, packaging, beta page | 2–4 wk |
| **NPU tier** | Windows ML execution providers for Copilot+ machines, if the CPU path leaves users wanting | open |

**Start with 0a and 0b.** Both are cheap, and together they decide most of the
plan. 0b's extraction also improves the Mac codebase if the port never happens.

## Open questions

1. **Is Ultra's NeMo checkpoint public?** It is CC-BY-4.0, but we have only seen
   it as FluidAudio's CoreML build. If no `.nemo` or PyTorch weights are
   released, Windows/Linux ship stock TDT v3, and the Mac and PC defaults differ
   in accuracy. Phase 0a measures by how much.
2. **One licence for any OS?** The recommendation is yes (see Licensing).
3. **Model hosting.** Corporate Windows networks block huggingface.co more often
   than home Macs do, and CLAUDE.md already records how a blocked HF hangs
   forever. Mirror the ONNX files on our own CDN with HF as fallback. This also
   pins the exact bytes we benchmarked.
4. **Who tests GNOME?** It is the most common Linux desktop and the weakest
   tier. Decide before L1 whether "Reduced" is acceptable to sell or whether
   GNOME is free/beta-only.

## Sources

- TDT v3 ONNX: [istupakov/parakeet-tdt-0.6b-v3-onnx](https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx) ·
  [sherpa-onnx int8 repackaged](https://huggingface.co/CreativeSkipper/MynaLuna-ASR)
- Parakeet Ultra card (mirror): [mixpeek.com/model/moondream/parakeet-ultra](https://mixpeek.com/model/moondream/parakeet-ultra)
- Nemotron 3.5 ONNX: [onnx-community int4](https://huggingface.co/onnx-community/nemotron-3.5-asr-streaming-0.6b-onnx-int4) ·
  [codavidgarcia export + engine](https://github.com/codavidgarcia/nemotron-3.5-asr-streaming-onnx) ·
  [sherpa-onnx #3664](https://github.com/k2-fsa/sherpa-onnx/issues/3664) ·
  [model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
- Nemotron EN on CPU: [OpenWhispr](https://openwhispr.com/blog/local-streaming-speech-to-text) ·
  [Softcery](https://softcery.com/lab/hosting-nemotron-asr-streaming-on-a-cpu)
- Precedent: [cjpais/Handy](https://github.com/cjpais/Handy) (Tauri, Parakeet v3 on CPU, Wayland via wtype/dotool)
- GlobalShortcuts portal: [GNOME support (TWIG #189)](https://thisweek.gnome.org/posts/2025/02/twig-189) ·
  [ashpd `Deactivated`](https://fractal-tobias-kuendig-a2308b584e67215e00d29986814e3bc2ee19fca1.pages.gitlab.gnome.org/src/ashpd/desktop/global_shortcuts.rs.html)
- Windows ML EP download: [AMD Ryzen AI WinML docs](https://ryzenai.docs.amd.com/en/latest/winml/winml_ep.html)
