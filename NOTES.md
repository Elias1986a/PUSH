# NOTES

## Current state (2026-08-12, v6.3.2)

Live preview shipped and working. Startup latency mostly fixed; one open thread.

### Open: 1072ms cold-press stall (causes TWO symptoms)

**Measured 2026-08-12 on v6.3.2 with real presses. Do not re-derive this.**

Warm presses: 216ms / 298ms / 244ms. Cold first press after launch: 1447ms.

    PressTiming: main-actor hop      +0ms      <- hop is instant
    PressTiming: chirp            +1072ms      <- 1072ms is HERE (74%)
    PressTiming: startRecording    +1072ms
    PressTiming: inputFormat       +1345ms     (+273)
    PressTiming: engine.start      +1445ms     (+100)
    PressTiming: beginDictation    +1447ms     (+2)
    PressTiming: recording started +1447ms

Ruled out by measurement: the `Task { @MainActor }` hop (0ms) and
`MediaController.beginDictation` (2ms). Both were my earlier hypotheses; both
were wrong.

Only two things sit between the hop and the chirp mark:
1. the pill window's FIRST render, triggered synchronously by
   `AppState.isListening = true` (didSet -> notifyStateChange ->
   updatePillVisibility -> sizePillToContent -> layoutSubtreeIfNeeded)
2. `SoundPlayer.playChirp()` first-time setup — it lazily builds an
   AVAudioPlayer from an mp3 inside a nested resource bundle
   (`PUSH_PUSH.bundle/nextel_chirp.mp3`)

**This also causes the "stuck pill" bug.** CGEvent taps are serviced on the
main thread and macOS disables any tap whose callback doesn't return promptly
(`kCGEventTapDisabledByTimeout`). The 1072ms block trips it — seen live:

    16:58:56  KEY DOWN
    16:58:57  Started recording (+1447ms)
    16:59:00  HotkeyManager: re-enabled event tap after system disabled it
    16:59:08  KEY UP        <- from the user's SECOND press

The release made during the disabled window was never delivered, so recording
ran on and the user had to press again to flush it. One root cause, two
symptoms — fix the stall and the dropped key-up should go with it.

**Plan:**
1. Add one `PressTiming` mark between `isListening = true` and `playChirp()`
   to prove which of the two owns the 1072ms.
2. Pre-warm both at launch, near `AudioRecorder.prewarm()`: `SoundPlayer`
   (load mp3 + `prepareToPlay()`) and a first render of the pill window.
3. Consider making the tap callback defensively cheap regardless — a slow main
   thread should never cost a key-up.
4. Ship with the already-committed status-text clipping fix as 6.3.3.

### Done: first-press latency 4s -> ~1.4s

Press → `AudioRecorder: Started recording` is ~2s on the first dictation after
launch (was 4s before v6.3.1). A cold `startRecording` measures only 0.16s, so
most of that gap is unaccounted for.

v6.3.1 delayed Sparkle 60s and pre-warmed the capture path. v6.3.2 added
`PressTiming`, which is still in the shipping build — to collect fresh data:
quit PUSH, reopen, wait for the menu bar mic, press and speak, then press a
second time, and compare first vs second in
`~/Library/Application Support/PUSH/push_debug.log`.

**Do not** re-litigate replacing Sparkle for the remaining stall — its own 4s
stall is off the critical path since v6.3.1, and the measured 1072ms is
demonstrably elsewhere. The user asked about switching updaters; the answer was
no (Sparkle is the mature open-source option; rolling your own means rebuilding
signature verification and atomic install). Revisit only with evidence.

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

### Uncommitted / unreleased

- Status-text clipping fix is COMMITTED but NOT released (fd8d5c0). It was held
  so an auto-update couldn't swap the binary mid-test. Ship it with 6.3.3.

### Notes
- Release builds now write `push_debug.log` (capped 512KB). `log show` never
  surfaced anything from release builds — that's why this went undiagnosed.
- The menu-bar hourglass is not a useful loading indicator (tracks only the ASR
  model, ready in 0.1s). Agreed with the user: don't build on it.
- Pushes to `main` bypass a branch-protection PR rule. User hasn't objected but
  hasn't explicitly approved either — worth asking.
