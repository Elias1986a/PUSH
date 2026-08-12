# NOTES

## Current state (2026-08-12, v6.3.3 — released)

Live preview shipped (6.2.x). Startup/press latency work closed out in 6.3.3.
Confirmed working in production by the user.

### The one thing to understand before touching this area

**Blocking the main thread breaks the hotkey.** The CGEvent tap's run loop
source lives on the main thread, and macOS disables any tap whose callback does
not return promptly (`kCGEventTapDisabledByTimeout`). The callback itself is
already trivial — the problem is that a blocked main thread never gets to *call*
it. Every symptom chased today traced back to this:

- ~4s main-thread warm-up → key-down never delivered, nothing happened at all
- ~1-2s block during a press → release swallowed, pill stuck holding the
  transcript until the user pressed a second time
- recovery was itself queued via `Task { @MainActor }`, i.e. behind the very
  stall that broke it — measured 9s to re-enable once

So: nothing on the launch path or the press path may block the main actor.

### Where the time actually goes (measured, do not re-derive)

Cold, first launch. `AudioRecorder.buildEngine()` logs these four parts:

    engine build — alloc 0ms, inputNode 3310ms, format 0ms, prepare 167ms

`engine.inputNode` — the first bind to the audio input HAL in the process — is
essentially the entire cost. Not our code. Machine has a **USB TONOR TM310** as
default input plus **eqMac's virtual driver**; untested whether the built-in mic
is faster. That test is the next useful data point if this comes up again: if
`inputNode` drops to a few hundred ms on the built-in mic, most users never see
a deaf window at all.

Press → recording, once warm: **110-140ms** (was 216-298ms).

### What 6.3.3 changed

- Warm-ups (capture engine, chirp) run **off the main thread**, started
  immediately and in parallel with the model load. Launch→warm ~5s → ~3.5s.
- One `AVAudioEngine` per process, stopped rather than discarded between
  recordings, rebuilt on `.AVAudioEngineConfigurationChange`. The old prewarm
  built a *local* engine that was released on return, tearing the device back
  down, so the first press paid the cold cost anyway (`inputFormat` 724ms → 0-2ms).
- A press landing mid-warm-up **joins the build already in flight** and awaits
  it. Starting a second engine and blocking on it cost 1336ms of pinned main
  thread while the background build finished moments later. `startRecording` is
  async for this and bails if the key is released first.
- `SoundPlayer`: warmed with a silent play, wound down with **`pause()`, never
  `stop()`** — `stop()` is documented to undo `prepareToPlay()`'s setup, which
  is why three earlier "prewarm" attempts still cost ~1s. `playChirp` also runs
  off the main actor and skips entirely if not yet warm.
- **Release watchdog**: while the key is held, a run-loop timer asks the hardware
  every 250ms whether the modifier is really still down, and ends the take if it
  isn't (two consecutive readings required). Confirmed catching a real dropped
  release. Deliberately evidence-independent — it doesn't care *why* an event
  went missing.
- Tap re-enabled **synchronously** inside the callback (already on the main run
  loop) rather than via a main-actor hop.
- `AppState.isCapturing` — the pill only says "Listening" once the mic is
  genuinely live. It used to say it through a measured 4.2s wait, and the user
  spoke the whole time into nothing.
- `AppState.isPrewarming` — warm-up indicator covers model + chirp + engine +
  VAD, not just `isModelReady` (which flips in ~0.1s and was a dishonest signal).
  Cleared in a `defer`, logged as `warm-up complete, indicator cleared`.
- `AppState.pillShouldShow` — single source of truth. The view and AppDelegate
  each had their own copy of the visibility condition; adding `isPrewarming` to
  only one meant the window was ordered out before the view could ever draw.
- Pill sizes itself via `NSHostingController.sizingOptions = .preferredContentSize`
  instead of hand-rolled refits. Every manual refit had to name the moments worth
  re-measuring, and each missed one clipped the text.

### How to measure this

Release builds log to `~/Library/Application Support/PUSH/push_debug.log`
(capped 512KB). `log show` surfaces nothing from release builds.

`PressTiming` is in the shipping build and prints offsets from key-down:

    main-actor hop → state set → chirp → startRecording enter → engine ready
      → inputFormat → engine.start → beginDictation → recording started

Compare a press right after launch against one a minute later. **Beware:** most
of today's "clean" runs were warm presses read as if they were cold — the cold
path stayed broken for hours behind that mistake.

For local test builds without notarising, see the throwaway script pattern:
`swift build -c release`, swap the binary + `.bundle` into an existing signed
`PUSH.app`, re-sign with the Developer ID (keeps the Accessibility grant), then
`open -n` it. `open` on the path alone can get redirected to `/Applications`.

### Open / next

- **Deaf window**: ~3.3s after launch where a press waits on the audio HAL. Only
  full fix is starting the engine at launch, which lights the system mic
  indicator — rejected by default for the same reason wake-word ships off.
  Test the built-in mic first.
- Event tap still runs on the main run loop. Moving it to a dedicated thread is
  the structural fix, but the two `nonisolated(unsafe)` Bools in the callback
  become a genuine cross-thread race, and event ordering must stay FIFO
  (`DispatchQueue.main.async`, not `Task`). Held back as too risky to bundle;
  the watchdog covers the observed failure.
- Pushes to `main` bypass a branch-protection PR rule (seven times now). Asked
  three times, never answered — either drop the rule or start opening PRs.
