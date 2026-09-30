import XCTest
@testable import PUSHCore

/// The Polar licence client against canned replies, shaped like Polar's
/// documented responses. Nothing here touches the network.
final class PolarLicenseTests: XCTestCase {

    /// Answers every request with whatever the test set, and records it.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var fail = false
        nonisolated(unsafe) static var lastPath = ""
        nonisolated(unsafe) static var lastBody: [String: Any] = [:]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lastPath = request.url?.path ?? ""
            if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                stream.close()
                Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }
            if Self.fail {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func client() -> PolarLicenseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return PolarLicenseClient(config: .sandbox, session: URLSession(configuration: config))
    }

    override func setUp() {
        StubProtocol.status = 200
        StubProtocol.body = Data()
        StubProtocol.fail = false
    }

    private func reply(_ status: Int, _ json: String) {
        StubProtocol.status = status
        StubProtocol.body = Data(json.utf8)
    }

    func testActivateSendsTheKeyTheOrganizationAndTheModelLabel() async throws {
        reply(200, #"{"id":"act-1","label":"Mac mini (M4)","license_key":{"display_key":"****-A1B2","limit_activations":3,"status":"granted"}}"#)
        let activation = try await client().activate(key: "  PUSH-KEY-A1B2 \n", label: "Mac mini (M4)")
        XCTAssertEqual(activation, LicenseActivation(activationID: "act-1", displayKey: "****-A1B2", activationLimit: 3))
        XCTAssertEqual(StubProtocol.lastPath, "/v1/customer-portal/license-keys/activate")
        XCTAssertEqual(StubProtocol.lastBody["key"] as? String, "PUSH-KEY-A1B2", "pasted whitespace is trimmed")
        XCTAssertEqual(StubProtocol.lastBody["organization_id"] as? String, PolarConfig.sandbox.organizationID)
        XCTAssertEqual(StubProtocol.lastBody["label"] as? String, "Mac mini (M4)")
    }

    func testEverySeatTakenIsRefusedWithPolarsReason() async {
        reply(403, #"{"error":"NotPermitted","detail":"License key activation limit reached"}"#)
        do {
            _ = try await client().activate(key: "K", label: "Mac")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? LicenseError, .refused(detail: "License key activation limit reached"))
        }
    }

    func testAnUnknownKeyIsNotFound() async {
        reply(404, #"{"error":"ResourceNotFound","detail":"Not found"}"#)
        do {
            try await client().validate(key: "K", activationID: "act-1")
            XCTFail("expected not found")
        } catch {
            XCTAssertEqual(error as? LicenseError, .notFound)
        }
    }

    /// Offline is not a verdict on the licence.
    func testNoNetworkIsUnreachableNotInvalid() async {
        StubProtocol.fail = true
        do {
            try await client().validate(key: "K", activationID: "act-1")
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? LicenseError, .unreachable)
        }
    }

    func testValidateAndDeactivateSendTheActivation() async throws {
        reply(200, #"{"status":"granted","display_key":"****-A1B2"}"#)
        try await client().validate(key: "K", activationID: "act-1")
        XCTAssertEqual(StubProtocol.lastPath, "/v1/customer-portal/license-keys/validate")
        XCTAssertEqual(StubProtocol.lastBody["activation_id"] as? String, "act-1")

        reply(204, "")
        try await client().deactivate(key: "K", activationID: "act-1")
        XCTAssertEqual(StubProtocol.lastPath, "/v1/customer-portal/license-keys/deactivate")
    }

    /// The model and chip, never the Mac's name.
    func testTheSeatLabelIsTheModelNotTheName() {
        XCTAssertEqual(MacModelLabel.label(productName: "Mac mini (2024)", chip: "Apple M4"), "Mac mini (M4)")
        XCTAssertEqual(MacModelLabel.label(productName: "MacBook Pro (14-inch, 2023)", chip: "Apple M3 Pro"), "MacBook Pro (M3 Pro)")
        XCTAssertEqual(MacModelLabel.label(productName: nil, chip: nil), "Mac")
        XCTAssertEqual(PolarLicenseClient.masked("ABCD-EFGH-1234"), "****-1234")
    }
}
