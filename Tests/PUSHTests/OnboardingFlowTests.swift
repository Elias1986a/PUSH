import XCTest
@testable import PUSH

final class OnboardingFlowTests: XCTestCase {
    /// The welcome carries the Talk and TYPE switches, so there is no separate
    /// features page in a normal setup (2026-10-14).
    func testDictationOnly() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false),
                       [.welcome, .permissions, .speechModel, .tryIt, .finish])
    }

    func testTypeOnlySkipsSpeechAndPill() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: true),
                       [.welcome, .permissions, .typingModel, .personal, .tryIt, .finish])
    }

    /// Seven pages, eight with the license: down from nine and ten.
    func testBoth() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: true),
                       [.welcome, .permissions, .speechModel, .typingModel, .personal, .tryIt, .finish])
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: true, licence: true).count, 8)
    }

    func testNeitherStopsAtTheWelcome() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, type: false), [.welcome])
    }

    /// The Type page stays, but "Make it yours" goes: nothing would use it.
    func testTypePageStaysWhenTypeIsSwitchedOffThere() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, typingSeen: true),
                       [.welcome, .permissions, .speechModel, .typingModel, .tryIt, .finish])
    }

    func testMicrophoneRowOnlyWithDictation() {
        XCTAssertTrue(OnboardingFlow.needsMicrophone(dictation: true))
        XCTAssertFalse(OnboardingFlow.needsMicrophone(dictation: false))
    }

    func testTheLicencePageFollowsTheWelcomeOnceTheStoreIsOpen() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, licence: true).prefix(3),
                       [.welcome, .licence, .permissions])
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: true).contains(.licence))
    }

    func testMakeItYoursComesAfterTheTypingModelWhenTypeIsOn() {
        let s = OnboardingFlow.steps(dictation: false, type: true)
        XCTAssertLessThan(s.firstIndex(of: .typingModel)!, s.firstIndex(of: .personal)!)
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: false).contains(.personal))
    }

    func testTheOtherMacQuestionComesFirst() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, type: false, otherMac: true).prefix(2),
                       [.otherMac, .welcome])
    }

    /// Copying skips the welcome, so the per-Mac switches get their own page;
    /// permissions, downloads, and the screen choices on "Make it yours" stay.
    func testCopyingSkipsWhatWasCopiedButNotWhatIsPerMac() {
        let s = OnboardingFlow.steps(dictation: true, type: true, otherMac: true, copied: true)
        XCTAssertEqual(s.first, .otherMac)
        XCTAssertFalse(s.contains(.welcome))
        for step in [OnboardingFlow.Step.features, .permissions, .speechModel, .typingModel, .personal, .finish] {
            XCTAssertTrue(s.contains(step), "\(step)")
        }
    }

    func testNoQuestionWhenNothingIsOnICloud() {
        XCTAssertFalse(OnboardingFlow.steps(dictation: true, type: true).contains(.otherMac))
    }
}
