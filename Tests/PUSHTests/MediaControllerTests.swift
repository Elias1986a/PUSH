import XCTest
@testable import PUSH
@testable import PUSHCore

/// Tests for MediaController's decision logic. The real audio mechanisms
/// (media key, CoreAudio volume) are injected as doubles — they were verified
/// separately against a signed binary, since they can't run in CI.
@MainActor
final class MediaControllerTests: XCTestCase {

    @MainActor
    private final class Harness {
        var volume: Float32? = 0.8
        var volumeWrites: [Float32] = []
        let defaults: UserDefaults

        init(suiteName: String) {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
        }

        func makeController() -> MediaController {
            MediaController(
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

    func testDuck_doubleBegin_onlyDucksOnce() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)
        controller.beginDictation(behavior: .duck)

        XCTAssertEqual(harness.volumeWrites.count, 1, "second begin must not re-duck an already-ducked volume")
        XCTAssertEqual(harness.volume ?? -1, 0.2, accuracy: 0.0001)
    }

    func testDuck_doubleEnd_onlyRestoresOnce() {
        let harness = makeHarness()
        harness.volume = 0.8
        let controller = harness.makeController()

        controller.beginDictation(behavior: .duck)
        controller.endDictation()
        harness.volumeWrites.removeAll()
        controller.endDictation()

        XCTAssertTrue(harness.volumeWrites.isEmpty)
    }

    func testEndWithoutBegin_doesNothing() {
        let harness = makeHarness()
        let controller = harness.makeController()

        controller.endDictation()

        XCTAssertTrue(harness.volumeWrites.isEmpty)
    }

    // MARK: - Off

    func testOff_touchesNothing() {
        let harness = makeHarness()
        let controller = harness.makeController()

        controller.beginDictation(behavior: .off)
        controller.endDictation()

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
