# NOTES

## Current state (2026-08-12, v6.3.2)

Live preview shipped and working. Startup latency mostly fixed; one open thread.

### Open: ~2s first-press latency

Press → `AudioRecorder: Started recording` is ~2s on the first dictation after
launch (was 4s before v6.3.1). A cold `startRecording` measures only 0.16s, so
most of that gap is unaccounted for.

**v6.3.2 ships `PressTiming`** to find it. Every milestone logs an offset from
key-down to `~/Library/Application Support/PUSH/push_debug.log`:

    PressTiming: main-actor hop +Nms
    PressTiming: chirp +Nms
    PressTiming: startRecording enter +Nms
    PressTiming: inputFormat +Nms
    PressTiming: engine.start +Nms
    PressTiming: beginDictation +Nms
    PressTiming: recording started +Nms

**To collect:** quit PUSH, reopen, wait for the menu bar mic, press the hotkey
and speak, then press a second time. Read the log and compare first vs second.

**Prime suspects:** the `Task { @MainActor }` hop in `HotkeyManager.handleKeyDown`,
and `MediaController.beginDictation` (synchronous CoreAudio volume work).

**Do not** re-litigate replacing Sparkle for this — its stall is off the
critical path since v6.3.1 (started 60s after launch) and there's no evidence
it's involved in the residual. Measure first.

### Recently fixed — read before touching startup

Two *separate* Sparkle problems, see memory `cold_start_unresolved`:
1. `startUpdater` opening an NSAlert deadlocked the serial main queue, wedging
   every main-actor continuation (v6.3.0).
2. `startUpdater` also stalls ~4s with no modal at all. v6.3.0 started it right
   after the model loaded (~0.1s), dropping that stall onto the user's first
   press — so v6.3.0 felt no better. v6.3.1 delays it 60s.

`AudioRecorder.prewarm()` now pays the capture path's lazy costs at launch
(inputFormat query + SileroVAD CoreML). It must NOT start the engine, or the
system mic indicator lights up at login.

### Notes
- Release builds now write `push_debug.log` (capped 512KB). `log show` never
  surfaced anything from release builds — that's why this went undiagnosed.
- The menu-bar hourglass is not a useful loading indicator (tracks only the ASR
  model, ready in 0.1s). Agreed with the user: don't build on it.
- Pushes to `main` bypass a branch-protection PR rule. User hasn't objected but
  hasn't explicitly approved either — worth asking.
