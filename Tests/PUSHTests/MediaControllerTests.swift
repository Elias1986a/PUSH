import XCTest
@testable import PUSH

/// Tests for MediaController's decision logic. The real audio mechanisms
/// (media key, CoreAudio volume) are injected as doubles — they were verified
/// separately against a signed binary, since they can't run in CI.
@MainActor
final class MediaControllerTests: XCTestCase {

    @MainActor
    private final class Harness {
        var playing = false
        var keyPresses = 0
        var volume: Float32? = 0.8
        var volumeWrites: [Float32] = []
        let defaults: UserDefaults

        init(suiteName: String) {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
        }

        func makeController() -> MediaController {
            MediaController(
                isAnythingPlaying: { self.playing },
                postPlayPauseKey: { self.keyPresses += 1 },
                currentVolume: { self.volume },
                setVolume: { value in
                    self.volume = value
                    self.volumeWrites.append(value)
                },
                defaults: defaults
            )
        }
    }

    private func makeHarness(_ name: String = #function) -> Harness {
        Harness(suiteName: "MediaControllerTests.\(name)")
    }

    // MARK: - Pause strategy

    func testPause_whenSomethingIsPlaying_sendsKeyOnceEachWay() {
        let harness = makeHarness()
        harness.playing = true
        let controller = harness.makeController()

        controller.beginDictation(behavior: .pause)
        XCTAssertEqual(harness.keyPresses, 1)

        controller.endDictation()
        XCTAssertEqual(harness.keyPresses, 2, "must toggle back so playback ends as it started")
    }

    /// The key is a blind toggle — sending it while nothing holds an audio
    /// stream would START playback the user never asked for.
    func testPause_whenNothingIsPlaying_sendsNothing() {
        let harness = makeHarness()
        harness.playing = false
        let controller = harness.makeController()

        controller.beginDictation(behavior: .pause)
        controller.endDictation()

        XCTAssertEqual(harness.keyPresses, 0)
    }

    func testPause_endWithoutBegin_doesNothing() {
        let harness = makeHarness()
        harness.playing = true
        let controller = harness.makeController()

        controller.endDictation()

        XCTAssertEqual(harness.keyPresses, 0)
    }

    func testPause_doubleEnd_onlyRestoresOnce() {
        let harness = makeHarness()
        harness.playing = true
        let controller = harness.makeController()

        controller.beginDictation(behavior: .pause)
        controller.endDictation()
        controller.endDictation()

        XCTAssertEqual(harness.keyPresses, 2)
    }

    /// Two rapid begins (e.g. a stop path racing a start) must not double-toggle.
    func testPause_doubleBegin_onlySendsOnce() {
        let harness = makeHarness()
        harness.playing = true
        let controller = harness.makeController()

        controller.beginDictation(behavior: .pause)
        controller.beginDictation(behavior: .pause)

        XCTAssertEqual(harness.keyPresses, 1)
    }

    // MARK: - Duck strategy

    func testDuck_lowersThenRestoresExactOriginal() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)
        XCTAssertEqual(harness.volume ?? -1, 0.2, accuracy: 0.0001, "0.8 * 0.25")

        controller.endDictation()
        XCTAssertEqual(harness.volume ?? -1, 0.8, accuracy: 0.0001)
    }

    func testDuck_whenVolumeUnavailable_doesNothing() {
        let harness = makeHarness()
        harness.volume = nil
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)
        controller.endDictation()

        XCTAssertTrue(harness.volumeWrites.isEmpty)
    }

    func testDuck_whenAlreadySilent_doesNothing() {
        let harness = makeHarness()
        harness.volume = 0
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)

        XCTAssertTrue(harness.volumeWrites.isEmpty)
    }

    // MARK: - Off

    func testOff_touchesNothing() {
        let harness = makeHarness()
        harness.playing = true
        let controller = harness.makeController()

        controller.beginDictation(behavior: .off)
        controller.endDictation()

        XCTAssertEqual(harness.keyPresses, 0)
        XCTAssertTrue(harness.volumeWrites.isEmpty)
    }

    // MARK: - Crash recovery

    func testInterruptedDuck_isRestoredAtNextLaunch() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()

        // Duck, then "crash" — endDictation never runs.
        controller.beginDictation(behavior: .duck)
        XCTAssertEqual(harness.volume ?? -1, 0.2, accuracy: 0.0001)

        // Next launch: a fresh controller sharing the same defaults.
        let next = harness.makeController()
        next.restoreVolumeIfInterrupted()

        XCTAssertEqual(harness.volume ?? -1, 0.8, accuracy: 0.0001)
    }

    /// If the user raised the volume themselves after the crash, don't stomp it.
    func testInterruptedDuck_doesNotOverrideAHigherUserVolume() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()
        controller.beginDictation(behavior: .duck)

        harness.volume = 0.9 // user turned it up
        harness.volumeWrites.removeAll()

        let next = harness.makeController()
        next.restoreVolumeIfInterrupted()

        XCTAssertTrue(harness.volumeWrites.isEmpty)
        XCTAssertEqual(harness.volume ?? -1, 0.9, accuracy: 0.0001)
    }

    func testCleanDuck_leavesNothingToRestore() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)
        controller.endDictation()
        harness.volumeWrites.removeAll()

        let next = harness.makeController()
        next.restoreVolumeIfInterrupted()

        XCTAssertTrue(harness.volumeWrites.isEmpty, "no stale marker after a clean run")
    }
}
