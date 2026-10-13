import XCTest
@testable import PUSHCore

final class LicenseKeyTextTests: XCTestCase {
    private let key = "1C3F2A9B-7D41-4E0A-9B2C-5F8E6D4A2E2C"

    func testFindsAKeyCopiedFromAnEmail() {
        XCTAssertEqual(LicenseKeyText.key(in: key), key)
        XCTAssertEqual(LicenseKeyText.key(in: "  \(key.lowercased())\n"), key)
        XCTAssertEqual(LicenseKeyText.key(in: "PUSH-\(key)"), "PUSH-\(key)")
    }

    func testIgnoresEverythingElse() {
        XCTAssertNil(LicenseKeyText.key(in: nil))
        XCTAssertNil(LicenseKeyText.key(in: ""))
        XCTAssertNil(LicenseKeyText.key(in: "Hi Sarah, thanks for the notes"))
        XCTAssertNil(LicenseKeyText.key(in: "Your key: \(key)"))
        XCTAssertNil(LicenseKeyText.key(in: "\(key) \(key)"))
        XCTAssertNil(LicenseKeyText.key(in: "****-82E2C5"))
    }

    func testReadsTheActivationLink() {
        XCTAssertEqual(LicenseKeyText.key(inActivationLink: URL(string: "pushtype://activate?key=\(key)")!), key)
        XCTAssertEqual(LicenseKeyText.key(inActivationLink: URL(string: "pushtype://activate?key=ABCD-1234-EF")!), "ABCD-1234-EF")
        XCTAssertNil(LicenseKeyText.key(inActivationLink: URL(string: "pushtype://activate?key=nope")!))
        XCTAssertNil(LicenseKeyText.key(inActivationLink: URL(string: "pushtype://activate?key=a%20b%3Cscript%3E")!))
        XCTAssertNil(LicenseKeyText.key(inActivationLink: URL(string: "pushtype://other?key=\(key)")!))
        XCTAssertNil(LicenseKeyText.key(inActivationLink: URL(string: "https://activate?key=\(key)")!))
    }
}
