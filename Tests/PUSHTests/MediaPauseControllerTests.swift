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
