import XCTest
@testable import PUSH

final class OnboardingFlowTests: XCTestCase {
    func testDictationOnlyMatchesTodaysWizardPlusFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false),
                       [.welcome, .features, .permissions, .speechModel, .tryIt, .finish])
    }

    func testTypeOnlySkipsSpeechAndPill() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: true),
                       [.welcome, .features, .permissions, .typingModel, .screenText, .tryIt, .finish])
    }

    func testBoth() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: true),
                       [.welcome, .features, .permissions, .speechModel, .typingModel, .screenText, .tryIt, .finish])
    }

    func testNeitherStopsAtFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: false), [.welcome, .features])
    }

    /// The Type page stays, but the screen page goes: nothing would use it.
    func testTypePageStaysWhenTypeIsSwitchedOffThere() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, typingSeen: true),
                       [.welcome, .features, .permissions, .speechModel, .typingModel, .tryIt, .finish])
    }

    func testMicrophoneRowOnlyWithDictation() {
        XCTAssertTrue(OnboardingFlow.needsMicrophone(dictation: true))
        XCTAssertFalse(OnboardingFlow.needsMicrophone(dictation: false))
    }
}
