import XCTest
@testable import PUSH

final class OnboardingFlowTests: XCTestCase {
    func testDictationOnlyMatchesTodaysWizardPlusFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false),
                       [.welcome, .features, .permissions, .speechModel, .tryIt, .finish])
    }

    func testTypeOnlySkipsSpeechAndPill() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: true),
                       [.welcome, .features, .permissions, .typingModel, .personal, .screenText, .tryIt, .finish])
    }

    func testBoth() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: true),
                       [.welcome, .features, .permissions, .speechModel, .typingModel, .personal, .screenText, .tryIt, .finish])
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

    func testTheLicencePageFollowsTheWelcomeOnceTheStoreIsOpen() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, licence: true).prefix(3),
                       [.welcome, .licence, .features])
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: true).contains(.licence))
    }

    func testTheLearningPageComesAfterTheTypingModelWhenTypeIsOn() {
        let s = OnboardingFlow.steps(dictation: false, type: true)
        XCTAssertLessThan(s.firstIndex(of: .typingModel)!, s.firstIndex(of: .personal)!)
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: false).contains(.personal))
    }

    func testTheOtherMacQuestionComesFirst() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, otherMac: true).prefix(2),
                       [.otherMac, .welcome])
    }

    /// Copying skips the welcome and the personal page, never permissions or downloads.
    func testCopyingSkipsWhatWasCopiedButNotWhatIsPerMac() {
        let s = OnboardingFlow.steps(dictation: true, type: true, otherMac: true, copied: true)
        XCTAssertEqual(s.first, .otherMac)
        XCTAssertFalse(s.contains(.welcome))
        XCTAssertFalse(s.contains(.personal))
        for step in [OnboardingFlow.Step.features, .permissions, .speechModel, .typingModel, .screenText, .finish] {
            XCTAssertTrue(s.contains(step), "\(step)")
        }
    }

    func testNoQuestionWhenNothingIsOnICloud() {
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: true).contains(.otherMac))
    }
}
