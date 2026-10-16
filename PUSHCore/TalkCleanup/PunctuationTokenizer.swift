import Foundation

/// SentencePiece unigram encoding for the fast punctuation model's 32k
/// lowercase vocabulary, matching `SentencePieceProcessor.EncodeAsIds` for
/// that model: identity normalizer, a dummy "▁" prefix, pieces never cross a
/// space (so a text can be encoded word by word), and an unknown character
/// costs the lowest piece score minus 10, with a run of unknowns merged into
/// one `<unk>`.
///
/// The vocabulary is `vocab.tsv` (piece, score, type per line), exported from
/// the model's `.model` file; only normal pieces (type 1) are matched.
public struct PunctuationTokenizer: Sendable {
    public static let unk: Int32 = 0, bos: Int32 = 1, eos: Int32 = 2, pad: Int32 = 3

    /// One token of a word: its id, and the unicode scalars of the word it
    /// covers (empty for the bare "▁" piece).
    public struct Token: Sendable, Equatable {
        public let id: Int32
        public let scalars: Range<Int>
        /// Whether the piece starts with "▁": its first character in the
        /// model's per-character outputs is that marker, not a letter.
        public let startsWord: Bool
    }

    private let pieces: [String: (id: Int32, score: Float)]
    private let maxPieceScalars: Int
    private let unknownScore: Float

    public init(vocabulary url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var pieces: [String: (Int32, Float)] = [:]
        var longest = 1
        var lowest = Float.greatestFiniteMagnitude
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, fields[2] == "1", let score = Float(fields[1]) else { continue }
            let piece = String(fields[0])
            pieces[piece] = (Int32(index), score)
            longest = max(longest, piece.unicodeScalars.count)
            lowest = min(lowest, score)
        }
        guard !pieces.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        self.pieces = pieces
        self.maxPieceScalars = longest
        self.unknownScore = lowest - 10
    }

    /// The tokens for one word (no spaces in it), "▁" prefix included.
    public func encode(word: String) -> [Token] {
        let scalars = Array(("\u{2581}" + word).unicodeScalars)
        let n = scalars.count
        guard n > 1 else { return [] }
        // Viterbi over scalar positions: best[i] is the best score of scalars[0..<i].
        var best = [Float](repeating: -.infinity, count: n + 1)
        var back = [(start: Int, id: Int32)](repeating: (0, PunctuationTokenizer.unk), count: n + 1)
        best[0] = 0
        for start in 0..<n where best[start] > -.infinity {
            var matchedSingle = false
            var piece = String.UnicodeScalarView()
            for end in (start + 1)...min(n, start + maxPieceScalars) {
                piece.append(scalars[end - 1])
                guard let entry = pieces[String(piece)] else { continue }
                if end == start + 1 { matchedSingle = true }
                let score = best[start] + entry.score
                if score > best[end] { best[end] = score; back[end] = (start, entry.id) }
            }
            if !matchedSingle {
                let score = best[start] + unknownScore
                if score > best[start + 1] { best[start + 1] = score; back[start + 1] = (start, PunctuationTokenizer.unk) }
            }
        }
        // Walk back, merging runs of unknowns as SentencePiece does.
        var tokens: [Token] = []
        var end = n
        while end > 0 {
            let (start, id) = back[end]
            if id == PunctuationTokenizer.unk, let last = tokens.last, last.id == PunctuationTokenizer.unk {
                tokens[tokens.count - 1] = Token(id: id, scalars: (start - 1)..<last.scalars.upperBound, startsWord: false)
            } else {
                // Scalar ranges are in the word itself, so the "▁" at 0 shifts everything by one.
                tokens.append(Token(id: id, scalars: max(0, start - 1)..<(end - 1), startsWord: start == 0))
            }
            end = start
        }
        return tokens.reversed()
    }

    /// Every word's tokens, in order. Words are split on spaces, which
    /// matches SentencePiece's own whitespace handling for this model.
    public func encode(_ text: String) -> [Int32] {
        text.split(separator: " ").flatMap { encode(word: String($0)).map(\.id) }
    }
}
