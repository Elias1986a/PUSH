import Foundation

/// Token healing's forced start, checked token by token instead of by a
/// grammar on every step.
///
/// llama.cpp's grammar sampler tests the whole vocabulary (262k tokens for
/// Gemma) each step, and the healing grammar kept doing so after its literal
/// was done, when it allows anything: 35 ms a token against 18 without it.
/// So the engine takes the model's own choice when it fits what is left of the
/// forced text, and asks a grammar only on a step where it does not.
public struct ForcedStart: Equatable, Sendable {
    /// Bytes of the forced text not yet produced.
    public private(set) var remaining: [UInt8]
    /// After the forced text, the next character must end the word.
    public private(set) var wordBoundary: Bool

    public init(_ forced: String, wordBoundary: Bool = false) {
        remaining = Array(forced.utf8)
        self.wordBoundary = wordBoundary && !forced.isEmpty
    }

    /// Nothing left to enforce: every token is fine from here on.
    public var isDone: Bool { remaining.isEmpty && !wordBoundary }

    /// Whether a token producing `piece` keeps to the forced start.
    public func fits(_ piece: [UInt8]) -> Bool {
        guard !isDone else { return true }
        guard !piece.isEmpty else { return false }
        if piece.count <= remaining.count {
            return remaining.starts(with: piece)
        }
        guard piece.starts(with: remaining) else { return false }
        return !wordBoundary || Self.isBoundary(piece[remaining.count...])
    }

    /// Records a token that `fits`.
    public mutating func advance(by piece: [UInt8]) {
        guard !isDone else { return }
        if piece.count <= remaining.count {
            remaining.removeFirst(piece.count)
        } else {
            remaining = []
            wordBoundary = false
        }
    }

    /// The grammar for what is left, for a step where the model's choice
    /// does not fit. Nil when the remainder is not whole UTF-8 (a token split
    /// a character): the caller then stops enforcing.
    public var grammar: String? {
        guard !isDone, let text = String(bytes: remaining, encoding: .utf8) else { return nil }
        return TokenHealing.grammar(forcing: text, wordBoundary: wordBoundary)
    }

    /// A space or punctuation: the grammar's boundary set.
    static func isBoundary(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard let first = bytes.first else { return false }
        if " ,.!?;:'\")".utf8.contains(first) { return true }
        return bytes.starts(with: "’".utf8)
    }
}
