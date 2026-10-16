import Foundation

/// One file in a Hugging Face model repo, resolved to the exact commit, size
/// and SHA-256 the download is then held to.
///
/// Type and the speech models carry these pins in the source. The Talk
/// cleanup models are on trial and were added from a session that could not
/// reach Hugging Face, so they resolve the repo's current commit when the
/// user presses Download: the file is still verified byte for byte against
/// that commit, but a later press could fetch a newer one. If a pass stays,
/// pin it like `TypingModel` before it ships.
public struct HuggingFaceFile: Sendable, Equatable {
    public let repo: String
    public let revision: String
    public let path: String
    public let bytes: Int64
    public let sha256: String

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(path)")!
    }

    public enum Failure: Error, LocalizedError {
        case badResponse(Int)
        case noMatchingFile(String)
        case notLargeFileStorage(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let status): return "Hugging Face answered \(status)."
            case .noMatchingFile(let suffix): return "No file ending in \(suffix) in the model repo."
            case .notLargeFileStorage(let path): return "\(path) has no checksum on Hugging Face."
            }
        }
    }

    private struct Info: Decodable { let sha: String }
    private struct Entry: Decodable {
        struct LFS: Decodable { let oid: String; let size: Int64 }
        let type: String
        let path: String
        let lfs: LFS?
    }

    /// The repo's current commit, and in it the file whose name ends in
    /// `suffix` (case-insensitive; the shortest name wins if several do).
    public static func resolve(repo: String, suffix: String,
                               session: URLSession = .shared) async throws -> HuggingFaceFile {
        let info: Info = try await get("https://huggingface.co/api/models/\(repo)", session: session)
        let tree: [Entry] = try await get("https://huggingface.co/api/models/\(repo)/tree/\(info.sha)", session: session)
        let candidates = tree.filter { $0.type == "file" && $0.path.lowercased().hasSuffix(suffix.lowercased()) }
        guard let entry = candidates.min(by: { $0.path.count < $1.path.count }) else {
            throw Failure.noMatchingFile(suffix)
        }
        // An LFS pointer's oid is the SHA-256 of the real file.
        guard let lfs = entry.lfs else { throw Failure.notLargeFileStorage(entry.path) }
        return HuggingFaceFile(repo: repo, revision: info.sha, path: entry.path, bytes: lfs.size, sha256: lfs.oid)
    }

    private static func get<T: Decodable>(_ url: String, session: URLSession) async throws -> T {
        let (data, response) = try await session.data(from: URL(string: url)!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else { throw Failure.badResponse(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
