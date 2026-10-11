import XCTest
@testable import PUSHCore

final class TypingSurfaceClassTests: XCTestCase {
    func testClassifiesKnownApps() {
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.mail"), .email)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.microsoft.VSCode"), .code)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.Notes"), .other)
        XCTAssertEqual(SurfaceClass.classify(bundleID: nil), .other)
    }

    func testVariantsMatchByPrefix() {
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.google.Chrome.canary"), .browser)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.microsoft.teams2"), .chat)
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.jetbrains.intellij"), .code)
    }

    func testPrefixNeedsAComponentBoundary() {
        // "com.apple.mail" must not swallow an unrelated "com.apple.mailfoo".
        XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.mailfoo"), .other)
    }
}
