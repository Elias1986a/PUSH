# Pause Media During Dictation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When dictation starts (hold-to-talk or wake-word), pause whatever media is currently playing system-wide, and resume it (only if we paused it) when dictation ends — with zero added latency to the hotkey-to-recording-starts path.

**Architecture:** A new `MediaPauseController` singleton owns a tiny state machine (`didPauseMedia` flag + in-flight check task) and depends on injected `sendCommand`/`fetchRate` closures for testability. A separate `MediaRemoteBridge` enum does the real `dlopen`/`dlsym` work against the private `MediaRemote.framework` and supplies those closures in production. `AudioRecorder.startRecording()`/`stopRecording()` are the only integration points, since both hold-to-talk and wake-word dictation route through them.

**Tech Stack:** Swift, XCTest, private `MediaRemote.framework` (dlopen/dlsym, macOS 15+).

**Design doc:** See `docs/plans/2026-08-08-media-pause-dictation-design.md` for the full rationale, rejected alternatives, and the empirically-measured latency numbers (30-50ms round trip, verified against Safari/YouTube — see that doc's "Latency" section).

---

### Task 1: `MediaPauseController` state machine (TDD)

**Files:**
- Create: `PUSH/Core/MediaPauseController.swift`
- Test: `Tests/PUSHTests/MediaPauseControllerTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import PUSH

@MainActor
final class MediaPauseControllerTests: XCTestCase {

    private func makeController(rate: Double?) -> (MediaPauseController, sent: () -> [Int]) {
        var sentCommands: [Int] = []
        let controller = MediaPauseController(
            sendCommand: { command in
                sentCommands.append(command)
                return true
            },
            fetchRate: { completion in completion(rate) }
        )
        return (controller, { sentCommands })
    }

    func testPauseIfPlaying_whenSomethingIsPlaying_sendsPauseAndFlagsPaused() async {
        let (controller, sent) = makeController(rate: 1.0)
        controller.pauseIfPlaying()
        // pauseIfPlaying kicks off an async Task; resumeIfWePaused awaits it,
        // so use it here purely to synchronize with the test.
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [MediaPauseController.kMRPause, MediaPauseController.kMRPlay])
    }

    func testPauseIfPlaying_whenNothingIsPlaying_doesNothing() async {
        let (controller, sent) = makeController(rate: 0.0)
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [])
    }

    func testPauseIfPlaying_whenRateUnavailable_doesNothing() async {
        let (controller, sent) = makeController(rate: nil)
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [])
    }

    func testResumeIfWePaused_withoutPriorPause_doesNothing() async {
        let (controller, sent) = makeController(rate: 1.0)
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [])
    }

    func testResumeIfWePaused_clearsFlagSoASecondResumeIsANoOp() async {
        let (controller, sent) = makeController(rate: 1.0)
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused()
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [MediaPauseController.kMRPause, MediaPauseController.kMRPlay])
    }

    func testPauseIfPlaying_calledTwiceWhileAlreadyPaused_doesNotDoubleSend() async {
        let (controller, sent) = makeController(rate: 1.0)
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused() // let the first check resolve and pause
        controller.pauseIfPlaying()
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused()
        XCTAssertEqual(sent(), [MediaPauseController.kMRPause, MediaPauseController.kMRPlay, MediaPauseController.kMRPause, MediaPauseController.kMRPlay])
    }

    func testResumeIfWePaused_racingAnInFlightPauseCheck_stillWaitsForIt() async {
        let sentBox = ActorBox<[Int]>([])
        let controller = MediaPauseController(
            sendCommand: { command in
                Task { await sentBox.append(command) }
                return true
            },
            fetchRate: { completion in
                // Simulate the real IPC round-trip latency so resumeIfWePaused()
                // is called while this is still in flight.
                Task {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    completion(1.0)
                }
            }
        )
        controller.pauseIfPlaying()
        await controller.resumeIfWePaused()
        let sent = await sentBox.value
        XCTAssertEqual(sent, [MediaPauseController.kMRPause, MediaPauseController.kMRPlay])
    }
}

actor ActorBox<T> {
    private(set) var value: T
    init(_ value: T) { self.value = value }
    func append<E>(_ element: E) where T == [E] { value.append(element) }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter MediaPauseControllerTests`
Expected: FAIL to compile — `MediaPauseController` doesn't exist yet.

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Pauses/resumes system media playback around dictation, so background
/// audio doesn't bleed into the recording. Uses injected closures so the
/// state machine (this type) can be tested without touching the real
/// MediaRemote framework — see `MediaRemoteBridge` for the production wiring.
@MainActor
final class MediaPauseController {
    static let shared = MediaPauseController()

    static let kMRPlay = 0
    static let kMRPause = 1

    private let sendCommand: (Int) -> Bool
    private let fetchRate: (@escaping (Double?) -> Void) -> Void

    private var didPauseMedia = false
    private var pauseCheckTask: Task<Void, Never>?

    convenience init() {
        if let bridge = MediaRemoteBridge.load() {
            self.init(sendCommand: bridge.sendCommand, fetchRate: bridge.fetchRate)
        } else {
            self.init(sendCommand: { _ in false }, fetchRate: { completion in completion(nil) })
        }
    }

    init(sendCommand: @escaping (Int) -> Bool, fetchRate: @escaping (@escaping (Double?) -> Void) -> Void) {
        self.sendCommand = sendCommand
        self.fetchRate = fetchRate
    }

    /// Fire-and-forget: never blocks the caller (AudioRecorder.startRecording
    /// must not gain latency from this).
    func pauseIfPlaying() {
        guard !didPauseMedia else { return }
        pauseCheckTask = Task { [weak self] in
            guard let self else { return }
            let rate = await self.currentRate()
            guard !Task.isCancelled, rate == 1.0 else { return }
            self.didPauseMedia = true
            _ = self.sendCommand(Self.kMRPause)
        }
    }

    /// Only resumes playback if `pauseIfPlaying()` actually paused something —
    /// never starts media that was already stopped/paused before dictation.
    func resumeIfWePaused() async {
        await pauseCheckTask?.value
        pauseCheckTask = nil
        guard didPauseMedia else { return }
        didPauseMedia = false
        _ = sendCommand(Self.kMRPlay)
    }

    private func currentRate() async -> Double? {
        await withCheckedContinuation { continuation in
            fetchRate { rate in continuation.resume(returning: rate) }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter MediaPauseControllerTests`
Expected: PASS (7 tests)

**Step 5: Commit**

```bash
git add PUSH/Core/MediaPauseController.swift Tests/PUSHTests/MediaPauseControllerTests.swift
git commit -m "feat: add MediaPauseController state machine for pausing media during dictation"
```

---

### Task 2: `MediaRemoteBridge` (real dlopen/dlsym integration)

No unit tests here — this talks to a real private OS framework, which can't be exercised in CI. Verified manually in Task 6. This mirrors the throwaway latency spike already run interactively (which proved this exact approach works: pause ~35-50ms, resume ~30-50ms against Safari/YouTube).

**Files:**
- Create: `PUSH/Core/MediaRemoteBridge.swift`

**Step 1: Write the bridge**

```swift
import Foundation

/// Thin dlopen/dlsym bridge to the private MediaRemote.framework — the same
/// mechanism behind Control Center's Now Playing widget and hardware media
/// keys. Loaded dynamically (never linked) since it's unversioned and could
/// disappear in a future macOS release; if so, `load()` returns nil and
/// MediaPauseController silently disables itself for the session.
enum MediaRemoteBridge {
    struct Handle {
        let sendCommand: (Int) -> Bool
        let fetchRate: (@escaping (Double?) -> Void) -> Void
    }

    private typealias SendCommandFn = @convention(c) (Int, AnyObject?) -> Bool
    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void

    static func load() -> Handle? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            PushLogger.log("MediaRemoteBridge: framework unavailable, media pause disabled")
            return nil
        }

        guard let sendPtr = dlsym(handle, "MRMediaRemoteSendCommand"),
              let infoPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            PushLogger.log("MediaRemoteBridge: expected symbols not found, media pause disabled")
            return nil
        }

        let sendCommand = unsafeBitCast(sendPtr, to: SendCommandFn.self)
        let getNowPlayingInfo = unsafeBitCast(infoPtr, to: GetNowPlayingInfoFn.self)

        return Handle(
            sendCommand: { command in sendCommand(command, nil) },
            fetchRate: { completion in
                getNowPlayingInfo(DispatchQueue.main) { info in
                    completion(info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double)
                }
            }
        )
    }
}
```

**Step 2: Build**

Run: `swift build`
Expected: Build complete, no errors.

**Step 3: Commit**

```bash
git add PUSH/Core/MediaRemoteBridge.swift
git commit -m "feat: add MediaRemoteBridge dlopen/dlsym wrapper for MediaRemote.framework"
```

---

### Task 3: `AppState.pauseMediaWhileDictating` setting

**Files:**
- Modify: `PUSH/App/AppState.swift:15` (UserDefaultsKeys), `:74-78` area (published var), `:232-235` area (init loader)

**Step 1: Add the UserDefaults key**

In the `UserDefaultsKeys` enum (`PUSH/App/AppState.swift:11-18`), add:

```swift
        static let pauseMediaWhileDictating = "pauseMediaWhileDictating"
```

**Step 2: Add the published property**

Right after `wakeWord` (`PUSH/App/AppState.swift:80-84`), add:

```swift
    /// Pauses system media playback (Music, Spotify, browser video, etc.)
    /// while recording, and resumes it afterward if we were the one that
    /// paused it. Defaults to true — most people dictating over media want
    /// this immediately.
    @Published var pauseMediaWhileDictating: Bool = true {
        didSet {
            UserDefaults.standard.set(pauseMediaWhileDictating, forKey: UserDefaultsKeys.pauseMediaWhileDictating)
        }
    }
```

**Step 3: Load the persisted value in `init()`**

Right after the `doubleSpaceAfterSentence` load block (`PUSH/App/AppState.swift:232-235`), add — using the same "only override the true default if a value was actually saved" pattern already used for `doubleSpaceAfterSentence`:

```swift
        // Load media-pause preference (default true when never set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.pauseMediaWhileDictating) != nil {
            self.pauseMediaWhileDictating = UserDefaults.standard.bool(forKey: UserDefaultsKeys.pauseMediaWhileDictating)
        }
```

**Step 4: Build**

Run: `swift build`
Expected: Build complete, no errors.

**Step 5: Commit**

```bash
git add PUSH/App/AppState.swift
git commit -m "feat: add pauseMediaWhileDictating setting to AppState"
```

---

### Task 4: Settings toggle

**Files:**
- Modify: `PUSH/Views/SettingsView.swift:48-61` (Hotkey section)

**Step 1: Add the toggle**

Right after `Toggle("Play sound when recording starts", isOn: $appState.playSoundOnStart)` (`PUSH/Views/SettingsView.swift:56`), add:

```swift
                Toggle("Pause media while dictating", isOn: $appState.pauseMediaWhileDictating)
```

**Step 2: Build**

Run: `swift build`
Expected: Build complete, no errors.

**Step 3: Commit**

```bash
git add PUSH/Views/SettingsView.swift
git commit -m "feat: add settings toggle for pausing media during dictation"
```

---

### Task 5: Wire into `AudioRecorder`

**Files:**
- Modify: `PUSH/Core/AudioRecorder.swift:74-96` (`startRecording`), `:99-118` (`stopRecording`)

**Step 1: Call `pauseIfPlaying()` on successful recording start**

In `startRecording(withVAD:)`, inside the `do` block right after `isRecording = true` (`PUSH/Core/AudioRecorder.swift:76`):

```swift
        do {
            try engine.start()
            isRecording = true

            if AppState.shared.pauseMediaWhileDictating {
                MediaPauseController.shared.pauseIfPlaying()
            }

            // Always run Silero VAD: gates transcription in hotkey mode,
```

(This only fires on a successful engine start, matching the design doc's call-out that pausing should only happen once recording is actually underway.)

**Step 2: Call `resumeIfWePaused()` on every stop**

In `stopRecording()`, right after the guard (`PUSH/Core/AudioRecorder.swift:99-101`):

```swift
    func stopRecording() async -> Data? {
        guard isRecording else { return nil }

        await MediaPauseController.shared.resumeIfWePaused()

        audioEngine?.inputNode.removeTap(onBus: 0)
```

This call is unconditional (not gated on the setting) — it's already a no-op via `didPauseMedia` when nothing was paused, and this covers every stop path (hold-to-talk release, VAD auto-stop, and Esc-cancel) with no duplicated logic, since all three route through this one function.

**Step 3: Build**

Run: `swift build`
Expected: Build complete, no errors.

**Step 4: Run full test suite**

Run: `swift test`
Expected: PASS, including the new `MediaPauseControllerTests`.

**Step 5: Commit**

```bash
git add PUSH/Core/AudioRecorder.swift
git commit -m "feat: pause/resume media playback around dictation recording"
```

---

### Task 6: Manual verification

Not TDD — this exercises the real MediaRemote framework, which needs an actual app and actual audio, so it isn't testable in CI.

1. `swift run` to launch PUSH.
2. Play a YouTube video in Safari. Hold the dictation hotkey — confirm audio pauses within ~50ms (imperceptible). Release the hotkey — confirm it resumes automatically after transcription completes.
3. Repeat with Music.app and with Spotify.
4. With nothing playing, hold the hotkey and dictate — confirm nothing starts playing afterward (the "don't wake sleeping media" edge case).
5. Pause a track yourself (e.g. hit spacebar in Music.app) *before* dictating — confirm it stays paused after dictation (we didn't pause it, so we shouldn't resume it).
6. Start dictation while media is playing, then press Esc to cancel — confirm media still resumes even though the dictation was discarded.
7. Toggle "Pause media while dictating" off in Settings — confirm media is left alone entirely during dictation.
8. Test the wake-word path (if enabled) the same way as step 2.

If any of these don't match, stop and re-diagnose before considering this done — don't mark it complete on the strength of the unit tests alone, since the real integration point (the private framework) is exactly what those tests stub out.
