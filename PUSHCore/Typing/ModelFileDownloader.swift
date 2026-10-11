import Foundation
import CryptoKit

/// Downloads one large file with byte progress, resume and a SHA-256 check.
///
/// Bytes land in `<destination>.partial`; an interrupted download resumes from
/// its size with a `Range` request. The hash is computed as the bytes arrive
/// (and over the existing partial first, when resuming), so a multi-GB file is
/// never read back just to check it. Only a file that matches both the size
/// and the checksum is moved to `destination`.
public final class ModelFileDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public struct Spec: Sendable, Equatable {
        public var url: URL
        public var bytes: Int64
        public var sha256: String

        public init(url: URL, bytes: Int64, sha256: String) {
            self.url = url
            self.bytes = bytes
            self.sha256 = sha256
        }
    }

    public enum Failure: Error, Equatable {
        case badResponse(Int), sizeMismatch, checksumMismatch
    }

    private let configuration: URLSessionConfiguration
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // State of the one transfer in flight; touched only on `queue`.
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var written: Int64 = 0
    private var expected: Int64 = 0
    private var partial: URL?
    private var onProgress: (@Sendable (Double) -> Void)?
    private var completion: CheckedContinuation<Void, Error>?
    /// Set by `finish` before it resumes the caller, which then reads it.
    private var digest = ""

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    public func download(_ spec: Spec, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: destination.path)[.size] as? Int64, size == spec.bytes {
            progress(1)
            return
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = URL(fileURLWithPath: destination.path + ".partial")
        var offset = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? 0
        if offset > spec.bytes {
            try? fm.removeItem(at: partial)
            offset = 0
        }
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }

        // Resume: the bytes already on disk go into the hash first.
        var hasher = SHA256()
        if offset > 0 { try Self.hash(partial, upTo: offset, into: &hasher) }

        var request = URLRequest(url: spec.url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.addOperation {
                    self.handle = try? FileHandle(forWritingTo: partial)
                    _ = try? self.handle?.seekToEnd()
                    self.hasher = hasher
                    self.written = offset
                    self.expected = spec.bytes
                    self.partial = partial
                    self.onProgress = progress
                    self.completion = continuation
                    if offset > 0 { progress(Double(offset) / Double(spec.bytes)) }
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }

        // Transfer done and the partial closed: check it, then move it in place.
        let size = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? -1
        guard size == spec.bytes else {
            try? fm.removeItem(at: partial)
            throw Failure.sizeMismatch
        }
        guard digest == spec.sha256.lowercased() else {
            try? fm.removeItem(at: partial)
            throw Failure.checksumMismatch
        }
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partial, to: destination)
        progress(1)
    }

    // MARK: - URLSessionDataDelegate (on `queue`)

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch status {
        case 206:
            completionHandler(.allow)
        case 200:
            // The server ignored the range (or there was none): start over.
            try? handle?.truncate(atOffset: 0)
            hasher = SHA256()
            written = 0
            completionHandler(.allow)
        default:
            completionHandler(.cancel)
            finish(throwing: Failure.badResponse(status))
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            finish(throwing: error)
            return
        }
        hasher.update(data: data)
        written += Int64(data.count)
        // Below 1 until the checksum has passed.
        onProgress?(min(Double(written) / Double(max(expected, 1)), 0.999))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(throwing: error) } else { finish(throwing: nil) }
    }

    private func finish(throwing error: Error?) {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard let completion else { return }
        self.completion = nil
        if let error { completion.resume(throwing: error) } else { completion.resume() }
    }

    static func hash(_ file: URL, upTo length: Int64, into hasher: inout SHA256) throws {
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        var remaining = length
        while remaining > 0 {
            guard let chunk = try reader.read(upToCount: Int(min(remaining, 8 << 20))), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= Int64(chunk.count)
        }
    }
}
