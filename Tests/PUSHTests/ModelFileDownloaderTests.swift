import XCTest
import CryptoKit
@testable import PUSHCore

/// Serves `StubServer.body` for any request, honouring `Range: bytes=N-`, and
/// can drop the connection after `failAfter` bytes or ignore ranges.
final class StubServer: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failAfter: Int?
    nonisolated(unsafe) static var ignoreRange = false
    nonisolated(unsafe) static var requestedRanges: [String?] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        Self.requestedRanges.append(range)
        var offset = 0
        if !Self.ignoreRange, let range, range.hasPrefix("bytes="), let n = Int(range.dropFirst(6).dropLast()) {
            offset = n
        }
        let slice = Self.body.subdata(in: offset..<Self.body.count)
        let status = offset > 0 ? 206 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(slice.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let failAfter = Self.failAfter, failAfter < slice.count {
            // Two chunks, so progress is observable, then the line drops.
            client?.urlProtocol(self, didLoad: slice.prefix(failAfter))
            // A real connection drops after its bytes have been delivered.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        let half = slice.count / 2
        client?.urlProtocol(self, didLoad: slice.prefix(half))
        client?.urlProtocol(self, didLoad: slice.suffix(from: half))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ModelFileDownloaderTests: XCTestCase {
    private var dir: URL!
    private let body = Data((0..<300_000).map { UInt8($0 % 251) })

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ModelFileDownloaderTests-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StubServer.body = body
        StubServer.failAfter = nil
        StubServer.ignoreRange = false
        StubServer.requestedRanges = []
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func spec(sha: String? = nil) -> ModelFileDownloader.Spec {
        .init(url: URL(string: "https://example.invalid/model.gguf")!, bytes: Int64(body.count),
              sha256: sha ?? SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
    }

    private func downloader() -> ModelFileDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return ModelFileDownloader(configuration: config)
    }

    private var destination: URL { dir.appendingPathComponent("model.gguf") }

    func testDownloadsVerifiesAndReportsProgress() async throws {
        let progress = ProgressLog()
        try await downloader().download(spec(), to: destination) { progress.append($0) }
        XCTAssertEqual(try Data(contentsOf: destination), body)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path + ".partial"))
        let seen = progress.values
        XCTAssertEqual(seen.last, 1)
        XCTAssertTrue(seen.contains { $0 > 0 && $0 < 1 }, "\(seen)")
        XCTAssertEqual(seen, seen.sorted())
    }

    func testResumesFromWhereTheLineDropped() async throws {
        StubServer.failAfter = 100_000
        do {
            try await downloader().download(spec(), to: destination) { _ in }
            XCTFail("should have thrown")
        } catch {}
        let partial = try Data(contentsOf: URL(fileURLWithPath: destination.path + ".partial"))
        XCTAssertEqual(partial.count, 100_000)

        StubServer.failAfter = nil
        try await downloader().download(spec(), to: destination) { _ in }
        XCTAssertEqual(StubServer.requestedRanges.last, "bytes=100000-")
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    func testServerThatIgnoresRangeStartsOver() async throws {
        try body.prefix(50_000).write(to: URL(fileURLWithPath: destination.path + ".partial"))
        StubServer.ignoreRange = true
        try await downloader().download(spec(), to: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    func testChecksumMismatchDeletesTheFileAndThrows() async throws {
        do {
            try await downloader().download(spec(sha: String(repeating: "0", count: 64)), to: destination) { _ in }
            XCTFail("should have thrown")
        } catch let error as ModelFileDownloader.Failure {
            XCTAssertEqual(error, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path + ".partial"))
    }

    func testAnExistingCompleteFileIsNotFetchedAgain() async throws {
        try body.write(to: destination)
        try await downloader().download(spec(), to: destination) { _ in }
        XCTAssertTrue(StubServer.requestedRanges.isEmpty)
    }
}

/// Progress arrives on the downloader's queue.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [Double] = []
    func append(_ value: Double) { lock.withLock { log.append(value) } }
    var values: [Double] { lock.withLock { log } }
}

/// Against Hugging Face itself: the Lite model (0.6 GB), cancelled partway and
/// resumed, then checked against the catalog's SHA-256. Opt-in:
/// `PUSH_TYPE_REAL_DOWNLOAD=1`.
final class ModelFileDownloaderLiveTests: XCTestCase {
    func testRealDownloadResumesAndVerifies() async throws {
        guard ProcessInfo.processInfo.environment["PUSH_TYPE_REAL_DOWNLOAD"] == "1" else {
            throw XCTSkip("PUSH_TYPE_REAL_DOWNLOAD not set")
        }
        let model = TypingModel.lite
        let spec = ModelFileDownloader.Spec(url: model.downloadURL, bytes: model.bytes, sha256: model.sha256)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent(model.file)

        let log = ProgressLog()
        let first = Task { try await ModelFileDownloader().download(spec, to: destination) { log.append($0) } }
        while (log.values.last ?? 0) < 0.3 { try await Task.sleep(for: .milliseconds(100)) }
        first.cancel()
        _ = try? await first.value
        let partialSize = try FileManager.default.attributesOfItem(atPath: destination.path + ".partial")[.size] as! Int64
        XCTAssertGreaterThan(partialSize, model.bytes / 4)

        let start = Date()
        try await ModelFileDownloader().download(spec, to: destination) { _ in }
        print("live download: resumed at \(partialSize / 1_000_000) MB, finished in \(Int(Date().timeIntervalSince(start)))s")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64, model.bytes)
    }
}
