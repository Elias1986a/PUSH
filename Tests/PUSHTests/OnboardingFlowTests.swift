import XCTest
@testable import PUSH

final class OnboardingFlowTests: XCTestCase {
    func testDictationOnlyMatchesTodaysWizardPlusFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false),
                       [.welcome, .features, .permissions, .speechModel, .tryIt, .pill, .more, .finish])
    }

    func testTypeOnlySkipsSpeechAndPill() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: true),
                       [.welcome, .features, .permissions, .typingModel, .tryIt, .more, .finish])
    }

    func testBoth() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: true),
                       [.welcome, .features, .permissions, .speechModel, .typingModel, .tryIt, .pill, .more, .finish])
    }

    func testNeitherStopsAtFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: false), [.welcome, .features])
    }

    func testMicrophoneRowOnlyWithDictation() {
        XCTAssertTrue(OnboardingFlow.needsMicrophone(dictation: true))
        XCTAssertFalse(OnboardingFlow.needsMicrophone(dictation: false))
    }
}
