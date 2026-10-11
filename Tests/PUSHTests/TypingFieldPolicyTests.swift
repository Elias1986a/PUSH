import XCTest
@testable import PUSHCore

final class TypingFieldPolicyTests: XCTestCase {
    func testSignInFieldsByLabel() {
        for label in ["Email or phone", "Username", "Enter PIN", "Verification code", "One-time code",
                      "Card number", "Log in", "E-mail address"] {
            XCTAssertTrue(FieldPolicy.isCredentialField(role: "AXTextField", labels: [label], domIdentifier: nil, text: nil),
                          label)
        }
    }

    func testProseLabelsWithACredentialWordAreOrdinary() {
        for label in ["Email subject", "Search email", "Message", "Shipping address", "Phonebook"] {
            XCTAssertFalse(FieldPolicy.isCredentialField(role: "AXTextField", labels: [label], domIdentifier: nil, text: nil),
                           label)
        }
    }

    func testSignInFieldsByWebID() {
        XCTAssertTrue(FieldPolicy.isCredentialField(role: "AXTextField", labels: [], domIdentifier: "user_email", text: nil))
        XCTAssertTrue(FieldPolicy.isCredentialField(role: "AXTextField", labels: [], domIdentifier: "loginEmail", text: nil))
        XCTAssertTrue(FieldPolicy.isCredentialField(role: "AXComboBox", labels: [], domIdentifier: "identifierId", text: nil))
        XCTAssertFalse(FieldPolicy.isCredentialField(role: "AXTextField", labels: [], domIdentifier: "emailSearch", text: nil))
    }

    func testTypedAddressMarksTheField() {
        XCTAssertTrue(FieldPolicy.isCredentialField(role: "AXTextField", labels: [], domIdentifier: nil, text: "elias@exam"))
        XCTAssertFalse(FieldPolicy.isCredentialField(role: "AXTextField", labels: [], domIdentifier: nil, text: "ping @team about it"))
    }

    func testMultiLineFieldsAreNeverCredentialFields() {
        // A body labelled "Email" is an email body: exactly where suggestions belong.
        XCTAssertFalse(FieldPolicy.isCredentialField(role: "AXTextArea", labels: ["Email"], domIdentifier: "email", text: nil))
    }

    func testMailOnlySuggestsInTheMessageBody() {
        XCTAssertTrue(FieldPolicy.isMailHeader(bundleID: "com.apple.mail", role: "AXTextField"))
        XCTAssertFalse(FieldPolicy.isMailHeader(bundleID: "com.apple.mail", role: "AXWebArea"))
        XCTAssertFalse(FieldPolicy.isMailHeader(bundleID: "com.apple.Notes", role: "AXTextField"))
    }
}
