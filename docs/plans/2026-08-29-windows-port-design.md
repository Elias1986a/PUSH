# Windows Port — Design

**Status:** planned, not committed. Written 2026-08-29 as a shelf document so the
decision can be made later with the analysis already done.

## Goal

A commercial Windows version of PUSH: same product — hold a hotkey, speak, text
lands in the focused field, all on-device — sold to a market roughly ten times
the size of the Mac one.

## Why this is a re-implementation, not a port

Of ~7,400 lines, only `PUSHCore/TextProcessing.swift` (928 lines) plus
`CorrectionsStore`/`ContextGate` are platform-neutral. The CoreML engines,
`AppleSpeechEngine`, SwiftUI views, the CGEvent tap, `AVAudioEngine` capture,
`NSPasteboard` injection and Sparkle have no Windows counterpart. The shared
asset is the design, not the code.

`CloudSync` rides iCloud key-value storage, which Windows cannot join. Windows v1
keeps the dictionary local; cross-platform sync needs a real backend and is out
of scope.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Hardware floor | Any x64 laptop, CPU-only | Widest market; the honest floor for a paid product. No NPU or GPU assumed. |
| Stack | C# / .NET 8 + WPF | Trivial P/Invoke, first-class ONNX Runtime bindings, Velopack updates, well-trodden transparent overlay. |
| ASR engine | **Open — decided by Phase 0** | See "The engine question" below. |
| v1 scope | Core loop + floating pill + dictionary/context gate | Streaming partials and wake word cut from v1. |
| Shared logic | Golden test-vector corpus | Both Swift and C# suites run one checked-in JSON corpus; drift fails CI. |
| Elevated apps | Detect and explain, don't support | See "UIPI" below. |

## Architecture

A single WPF app, `Push.exe`, in four layers. Data flows one way:
hook → recorder → VAD → engine → core → injector, mirroring `TranscriptionPipeline`.

- **`Push.Core`** — no Windows dependencies, unit-testable. Port of
  `TextProcessing`, `CorrectionsStore`, `ContextGate`. Pure functions over
  strings. This is what the golden corpus tests.
- **`Push.Audio`** — WASAPI capture (NAudio), resampled to 16 kHz mono float.
  Silero VAD as ONNX — **the same `.onnx` file the Mac ships**, not a
  reimplementation.
- **`Push.Asr`** — `IAsrEngine` with one implementation over ONNX Runtime, int8,
  CPU execution provider. The interface exists so a DirectML/CUDA EP can slot in
  later. Mirrors the `ModelLoader` rule: only this layer loads or unloads models.
- **`Push.App`** — WPF. Tray icon, settings, pill overlay (transparent, topmost,
  `WS_EX_NOACTIVATE | WS_EX_TRANSPARENT` so it never steals focus), and the two
  Win32 interop pieces below.

## The engine question

**The current model lineup was chosen on Apple Neural Engine benchmarks and that
evidence does not transfer.** `WhisperModel.swift` records the deciding figure —
Parakeet Unified at 8.3 s of audio in 0.061 s vs Whisper Large v3 Turbo's 1.106 s,
an RTF of ~0.007. That is what an ANE does. A 600M-parameter encoder at int8 on a
2020 i5 is a different proposition entirely.

Two facts that constrain the choice:

- Whisper and Moonshine were removed in v7.0.0 (`a6a4c9d`). Moonshine never
  worked — its weights only ever existed in the upstream package's test
  resources and were never shipped. It was cut as dead code, not on merit.
- **Parakeet Unified is FluidAudio's CoreML packaging.** The Parakeet with a
  public ONNX export is **TDT v2** — the 400 MB model the UI labels "Older
  English model." Windows cannot inherit the current default.

So Phase 0 is a bake-off, not a validation. Candidates: Parakeet TDT v2 int8;
Moonshine Base (61M params vs 600M, ONNX-native, no 30-second padding, built for
edge CPU); whisper-small.en int8 as control. Ship the top two behind an in-app
toggle — models get judged by feel, not by leaderboard.

## Windows-specific traps

**1. The low-level hook timeout is the CGEvent tap again.** Windows silently
stops calling a `WH_KEYBOARD_LL` hook whose callback exceeds
`LowLevelHooksTimeout` (~300 ms, `HKCU\Control Panel\Desktop`) — the same failure
mode as blocking the main thread on macOS and losing key-up. Mitigation is
structural: the hook owns a dedicated thread with its own message pump, and the
callback only enqueues and returns.

**2. UIPI blocks injection into elevated windows.** An unelevated PUSH cannot
paste into Task Manager or an admin shell; `SendInput` is dropped with no error.
v1 checks the foreground window's integrity level before injecting and has the
pill say *"PUSH can't type into apps running as administrator."* Running the whole
app elevated would make every update prompt UAC and make an always-on keyboard
hook look far more suspicious. The proper fix (`uiAccess="true"`) needs a signed
binary under Program Files — revisit only if this turns out to matter.

**3. The clipboard is globally contended.** Unlike `NSPasteboard`, `OpenClipboard`
can fail outright because another process holds it; needs bounded retry with
backoff. The macOS fix — snapshot the clipboard *while recording*, not at inject
time (`244fc3f`) — carries over verbatim.

**4. PUSH looks exactly like a keylogger.** Global hook + clipboard + synthetic
input is the malware signature. This makes signing a launch blocker and AV
submissions a scheduled task, not a contingency.

**5. Per-monitor DPI** for the pill across mixed-DPI setups.

## Distribution and licensing

- **Signing:** Azure Trusted Signing (~$10/month, individual validation
  available). OV builds SmartScreen reputation over downloads; EV grants it
  immediately — worth the difference for a security-shaped app.
- **Installer:** per-user into `%LocalAppData%`, no UAC at install time. Velopack
  gives signed delta auto-updates against a static feed, the Sparkle equivalent.
  Skip MSIX — containerization fights a global hook. *Tension:* per-user install
  rules out the `uiAccess` fix later.
- **Licensing is net-new on both platforms** — no purchase, trial or license code
  exists in the Mac app today. Offline product, so: activate online once, cache a
  signed entitlement token, verify offline against a public key, re-check on a
  long interval with a generous grace period. Never phone home per-dictation.
- **Storefront:** a merchant of record (Paddle or Lemon Squeezy) rather than raw
  Stripe — they absorb global VAT/sales-tax registration.

## Roadmap

Phases are kill gates, not a march. Each either buys information cheaply or stops
the project.

| Phase | Work | Effort | Gate |
|---|---|---|---|
| **0** | **Engine bake-off.** Console harness on a floor-spec x64 box. Three engines, same WAVs, WER + wall-clock per stage. No app code. | ~1 wk | **p50 ≤ ~700 ms** speech-end-to-text on a 5 s utterance. Nothing passes → the hardware floor moves or the product doesn't exist. |
| **1** | **Walking skeleton.** Hook thread → WASAPI → Silero → engine → clipboard paste. Tray icon only. | 2–3 wk | Does it actually type into Chrome, Word, Slack, VS Code, Windows Terminal? |
| **2** | **`Push.Core` + golden corpus.** Extract the corpus from the Swift tests, then port until both suites pass it. Pure C#, no Windows knowledge needed. | 2–3 wk | Both suites green on one corpus. |
| **3** | **Product surface.** Pill overlay, settings, model download with progress, launch at login, mic consent. | 3–4 wk | — |
| **4** | **Distribution.** Trusted Signing, Velopack, update feed, AV false-positive submissions. | ~2 wk | Clean install/update/uninstall; no SmartScreen wall. |
| **5** | **Licensing.** Merchant of record, offline entitlement token. Shared with macOS. | 2–3 wk | — |

**Realistic total: 12–17 focused weeks.**

Phase 2 has no dependency on Phases 0–1 and needs no Windows knowledge, so it is
the cheap way to make progress while undecided. But **Phase 0 is the one that
matters** — one week, and it greenlights or kills everything after it.
