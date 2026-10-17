import Foundation

/// One file in a Hugging Face model repo, pinned to the exact commit, size
/// and SHA-256 the download is held to.
public struct HuggingFaceFile: Sendable, Equatable {
    public let repo: String
    public let revision: String
    public let path: String
    public let bytes: Int64
    public let sha256: String

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(path)")!
    }
}
