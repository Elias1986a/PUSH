# Pause media during dictation

## Problem

When PUSH records dictation (hold-to-talk or wake-word), background media
(music, video) bleeds into the mic and can drown out speech. We want PUSH to
pause whatever's playing when recording starts and resume it when recording
ends.

## Mechanism

Use the private `MediaRemote.framework` (loaded via `dlopen`/`dlsym`, not
linked at build time) to send real pause/play commands to whatever app
currently owns the system's "Now Playing" state — the same mechanism behind
the Control Center now-playing widget and hardware media keys. This gives
true silence (not just a volume duck) and works across native apps (Music,
Spotify) and browser tabs (Safari/Chrome playing YouTube, etc.) uniformly.

Rejected alternative: ducking system output volume via CoreAudio. Simpler
API, but doesn't fully silence audio and also dips notification/UI sounds.

## Latency

Verified empirically (see spike results below) rather than assumed, since
this was a hard gate: the whole feature is scrapped if it adds perceptible
latency to hold-to-talk.

- `MRMediaRemoteSendCommand` call itself: ~0.5-2ms (fire-and-forget, non-blocking).
- Round-trip until system reports the new state (paused/playing): consistently
  30-50ms across 3 trials, for both pause and resume, tested against a YouTube
  video in Safari.

Since the command is sent in parallel with recording start (never blocking
`AudioRecorder.startRecording()`), this adds **zero** latency to the
hotkey-to-recording-starts path. The only cost is a ~30-50ms window where
background audio may still be briefly audible at the very start of the
recorded clip — acceptable, since VAD/ASR tolerate a fraction of a second of
background noise.

## Architecture

New singleton `MediaPauseController` in `PUSH/Core/`, hooked into exactly one
integration point: `AudioRecorder.swift`, since both hold-to-talk
(`HotkeyManager.handleKeyDown`/`handleKeyUp`) and wake-word dictation route
through `AudioRecorder.startRecording()` / `stopRecording()`
(`PUSH/Core/AudioRecorder.swift:32,99`). This also automatically covers the
Esc-cancel path (`HotkeyManager.handleCancelRecording()`, line 359), since it
calls `stopRecording()` too.

```
AudioRecorder.startRecording()  -> MediaPauseController.shared.pauseIfPlaying()
AudioRecorder.stopRecording()   -> MediaPauseController.shared.resumeIfWePaused()
```

## State tracking

`MediaPauseController` must remember whether *it* paused media, so it never
resumes something that was already paused/idle before dictation started
(e.g. don't start Music.app playing just because the user held the hotkey
with nothing playing).

```swift
private var didPauseMedia = false

func pauseIfPlaying() {
    fetchRate { rate in
        guard rate == 1.0 else { return }   // nothing playing -> no-op
        self.didPauseMedia = true
        sendCommand(kMRPause, nil)
    }
}

func resumeIfWePaused() {
    guard didPauseMedia else { return }
    didPauseMedia = false
    sendCommand(kMRPlay, nil)
}
```

`fetchRate` is async, so `pauseIfPlaying()` doesn't block recording start.
Edge case: if `resumeIfWePaused()` is called before the async `pauseIfPlaying()`
check has resolved, the resume must wait for that check to settle rather than
silently dropping it (short dictations could otherwise race this).

## Error handling

- **Framework unavailable** (private API, could break on a future macOS):
  fail silently and disable the feature for the session. Never block or
  degrade dictation because this nice-to-have couldn't load. Log via
  `PushLogger` (operational only — no transcript content).
- **Nothing playing**: `rate == 1.0` guard in `pauseIfPlaying()` is a no-op.
- **Multiple audio sources**: MediaRemote reflects whichever app currently
  owns Now Playing — same source of truth as Control Center / hardware media
  keys, so behavior matches what the user already expects.
- **Rapid re-triggering**: guard `pauseIfPlaying()` on `didPauseMedia` already
  being `true` to avoid double-pausing.

## Settings

New `@Published var pauseMediaWhileDictating: Bool = true` in `AppState.swift`,
persisted via `UserDefaultsKeys`, following the same pattern as
`wakeWordEnabled`. Toggle added to `SettingsView.swift`. Defaults to **on**.
`AudioRecorder` checks this flag before calling into `MediaPauseController`.

## Testing

No CI audio session, so real MediaRemote IPC can't be exercised in
`Tests/PUSHTests`. Plan:
- Unit test `MediaPauseController`'s state machine (`didPauseMedia` transitions)
  against an injected fake command-sender/rate-fetcher.
- Manual verification against Music.app, Spotify, and Safari/YouTube for the
  pause/resume/no-op paths, plus the Esc-cancel path.
