import Foundation
import NaturalLanguage

/// Spoken numbers into digits: AP style, decimals, years and ordinals.
///
/// Split out of `TextProcessing.swift`; see that file for the pipeline itself.
extension TranscriptionPipeline {
    // MARK: - Number Normalization (AP style + decimal dictation)

    /// Spelled-out number words and their integer values.
    private static let baseNumberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100, "thousand": 1000, "million": 1_000_000
    ]

    // Sorted longest-first so e.g. "seventeen" wins over "seven" in alternation.
    private static let numberWordPattern: String =
        baseNumberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let decimalWordPattern: String =
        (Array(baseNumberWords.keys) + ["oh"]).sorted { $0.count > $1.count }.joined(separator: "|")
    /// Same, minus the magnitudes. The fractional side of a dictated decimal must
    /// not swallow them: "four point eight million" is 4.8 million, and absorbing
    /// "million" into the fraction produced "4.8000000".
    private static let decimalFractionWordPattern: String =
        (baseNumberWords.keys.filter { !["hundred", "thousand", "million"].contains($0) } + ["oh"])
            .sorted { $0.count > $1.count }.joined(separator: "|")

    /// Spelled-out ordinal words mapped to their cardinal value.
    /// Suffix (st/nd/rd/th) is derived from the final combined value, not stored here.
    private static let ordinalWords: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40,
        "fiftieth": 50, "sixtieth": 60, "seventieth": 70, "eightieth": 80,
        "ninetieth": 90, "hundredth": 100, "thousandth": 1000, "millionth": 1_000_000
    ]
    private static let ordinalWordPattern: String =
        ordinalWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    /// Magnitude words are multipliers, not numbers in their own right.
    private static let magnitudeWords: Set<String> = ["hundred", "thousand", "million"]

    /// True when a run is nothing but magnitude words ("million", "hundred thousand").
    /// Such a run has no multiplier of its own: either the multiplier is already
    /// digits sitting outside the run ("4.8 million", "$5 million") or there is
    /// none at all and the word is prose ("a hundred people"). Expanding it uses
    /// `parseNumberRun`'s implicit multiplier of 1 and invents a number —
    /// "4.8 million" became "4.8 1,000,000".
    public static func isBareMagnitudeRun(_ run: String) -> Bool {
        let words = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        return !words.isEmpty && words.allSatisfy { magnitudeWords.contains($0) }
    }

    /// Parse a contiguous run of number words ("twenty five", "one hundred five") into an Int.
    /// Returns nil if any token isn't recognized. `allowOh` enables "oh" → 0 for decimal contexts.
    public static func parseNumberRun(_ run: String, allowOh: Bool = false) -> Int? {
        let words = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return nil }

        var total = 0
        var current = 0
        for word in words {
            let value: Int
            if let v = baseNumberWords[word] {
                value = v
            } else if allowOh && word == "oh" {
                value = 0
            } else {
                return nil
            }

            if value == 100 {
                current = (current == 0 ? 1 : current) * 100
            } else if value >= 1000 {
                total += (current == 0 ? 1 : current) * value
                current = 0
            } else {
                current += value
            }
        }
        return total + current
    }

    /// Parse the fractional side of a dictated decimal into its digits.
    /// "one four" is 14, not 5 — pi is dictated "three point one four", and summing
    /// the run gave "3.5". But "twenty five" is 25, not "205". The rule that splits
    /// them: a run of nothing but single digits concatenates, anything else parses
    /// arithmetically.
    public static func parseDecimalFraction(_ run: String) -> String? {
        let words = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return nil }

        var digits = ""
        for word in words {
            let value: Int
            if word == "oh" {
                value = 0
            } else if let v = baseNumberWords[word] {
                value = v
            } else {
                return nil
            }
            guard value <= 9 else {
                // Not a pure digit run — fall back to arithmetic ("twenty five" → 25).
                return parseNumberRun(run, allowOh: true).map(String.init)
            }
            digits.append(String(value))
        }
        return digits
    }

    /// Rewrite "X point Y [point Z]" dictation as "X.Y[.Z]" (versions, decimals).
    /// "four point zero point two" → "4.0.2"; "ten point five" → "10.5".
    public static func normalizeDecimalDictation(_ text: String) -> String {
        // The integer side may carry magnitudes ("one hundred point five" → 100.5);
        // the fractional side may not (see decimalFractionWordPattern).
        let intWord = decimalWordPattern
        let fracWord = decimalFractionWordPattern
        let intChunk = "(?:\(intWord))(?:[\\s-]+(?:\(intWord)))*"
        let fracChunk = "(?:\(fracWord))(?:[\\s-]+(?:\(fracWord)))*"
        let pattern = "\\b\(intChunk)(?:\\s+point\\s+\(fracChunk))+\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let splitter = try? NSRegularExpression(pattern: "\\s+point\\s+", options: .caseInsensitive) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [],
                                    range: NSRange(location: 0, length: nsText.length))

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let runText = String(result[range])

            var pieces: [String] = []
            var lastEnd = runText.startIndex
            let nsRun = runText as NSString
            for m in splitter.matches(in: runText, options: [],
                                      range: NSRange(location: 0, length: nsRun.length)) {
                guard let r = Range(m.range, in: runText) else { continue }
                pieces.append(String(runText[lastEnd..<r.lowerBound]))
                lastEnd = r.upperBound
            }
            pieces.append(String(runText[lastEnd...]))

            var digits: [String] = []
            var ok = true
            for (i, piece) in pieces.enumerated() {
                // Integer side parses arithmetically; every side after a "point"
                // is a fraction and follows the digit-concatenation rule.
                let parsed = i == 0
                    ? parseNumberRun(piece, allowOh: true).map(String.init)
                    : parseDecimalFraction(piece)
                if let v = parsed {
                    digits.append(v)
                } else { ok = false; break }
            }
            if ok && digits.count >= 2 {
                result.replaceSubrange(range, with: digits.joined(separator: "."))
            }
        }
        return result
    }

    /// AP style: spelled numbers ≥10 → digits, 1–9 stay spelled. Existing digits untouched.
    /// "twenty-five years" → "25 years"; "five apples" stays; "one hundred five" → "105".
    /// A run of nothing but magnitude words stays spelled: "4.8 million", "a hundred people".
    public static func normalizeNumberWords(_ text: String) -> String {
        let word = numberWordPattern
        let pattern = "\\b(?:\(word))(?:[\\s-]+(?:\(word)))*\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [],
                                    range: NSRange(location: 0, length: nsText.length))

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let runText = String(result[range])
            if isBareMagnitudeRun(runText) { continue }
            // Years are never comma-grouped, so they bypass formatSpokenNumber.
            if let year = parseSpokenYear(runText) {
                result.replaceSubrange(range, with: String(year))
            } else if let value = parseNumberRun(runText), value >= 10 {
                result.replaceSubrange(range, with: formatSpokenNumber(value))
            }
        }
        return result
    }

    /// Comma-group a bare digit string. No length rule — callers decide what to group.
    public static func insertThousandsSeparators(_ digits: String) -> String {
        var grouped = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return grouped
    }

    /// Render a number that was *spoken as words*. Such a number gets separators
    /// from 1,000 up, where `groupThousands` starts at five digits: that pass sees
    /// only digits and can't tell a count from a year or a port, so it has to leave
    /// every 4-digit run alone. Words carry the provenance digits lost — "one
    /// thousand people" is a count, and came out as "1000 people".
    ///
    /// The exception is the spoken-year shape — 1000–2999 with a 1–99 remainder,
    /// i.e. "two thousand twenty four" — which stays "2024".
    public static func formatSpokenNumber(_ value: Int) -> String {
        guard value >= 1000 else { return String(value) }
        let remainder = value % 1000
        let isYearLike = (1000...2999).contains(value) && (1..<100).contains(remainder)
        return isYearLike ? String(value) : insertThousandsSeparators(String(value))
    }

    /// Years dictated as two pairs: "nineteen ninety nine" → 1999,
    /// "twenty twenty four" → 2024. `parseNumberRun` sums them — 19 + 90 + 9 = 118 —
    /// because it has no notion of a pair.
    ///
    /// The tell is arithmetic that isn't English: no number is formed by adding two
    /// values ≥ 10 in sequence, so the second one must start a second pair. That
    /// leaves ordinary compounds alone — "twenty five" adds 5 to 20 and never
    /// splits. Magnitude words disqualify the run outright ("two thousand twenty
    /// four" is already handled), and the result must land in 1000–2999 so that a
    /// "sixty forty split" doesn't become 6040.
    public static func parseSpokenYear(_ run: String) -> Int? {
        let words = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard words.count >= 2 else { return nil }

        var values: [Int] = []
        for word in words {
            guard let v = baseNumberWords[word], v < 100 else { return nil }
            values.append(v)
        }

        var running = 0
        var splitIndex: Int?
        for (i, v) in values.enumerated() {
            if running >= 10 && v >= 10 { splitIndex = i; break }
            running += v
        }
        guard let split = splitIndex, split > 0 else { return nil }

        let high = values[..<split].reduce(0, +)
        let low = values[split...].reduce(0, +)
        guard (10...99).contains(high), (0...99).contains(low) else { return nil }
        let year = high * 100 + low
        return (1000...2999).contains(year) ? year : nil
    }

    /// Insert thousands separators into large integer runs: "30000000" → "30,000,000".
    /// Only 5+ digit runs are grouped — 4-digit values (years, ports) are ambiguous
    /// and stay as-is. Runs adjacent to a dot, comma, or digit (decimal fractions,
    /// already-grouped numbers) are left untouched.
    public static func groupThousands(_ text: String) -> String {
        let pattern = "(?<![\\d.,])\\d{5,}(?!\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [],
                                    range: NSRange(location: 0, length: nsText.length))

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: insertThousandsSeparators(String(result[range])))
        }
        return result
    }

    /// "st"/"nd"/"rd"/"th" suffix for an ordinal value (11–13 are always "th").
    public static func ordinalSuffix(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// Parse a run whose final token is an ordinal word into (value, suffix).
    /// Prefix tokens may be number words, digits, or "and": "twenty fifth" → (25, "th"),
    /// "one hundred and fifth" → (105, "th"), "20 fifth" → (25, "th").
    public static func parseOrdinalRun(_ run: String) -> (value: Int, suffix: String)? {
        let tokens = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        guard let last = tokens.last, let ordVal = ordinalWords[last] else { return nil }
        // Bare "first"/"second" double as everyday words ("first of all", "wait a second");
        // only convert them when part of a compound ordinal ("twenty second" → "22nd").
        if tokens.count == 1, last == "first" || last == "second" { return nil }

        var total = 0
        var current = 0
        for (i, tok) in tokens.enumerated() {
            let value: Int
            if i == tokens.count - 1 {
                value = ordVal
            } else if tok == "and" {
                continue
            } else if let v = baseNumberWords[tok] {
                value = v
            } else if let d = Int(tok) {
                value = d
            } else {
                return nil
            }

            if value == 100 {
                current = (current == 0 ? 1 : current) * 100
            } else if value >= 1000 {
                total += (current == 0 ? 1 : current) * value
                current = 0
            } else {
                current += value
            }
        }
        let n = total + current
        return (n, ordinalSuffix(n))
    }

    /// Spelled-out ordinals → figures: "fifth" → "5th", "twenty fifth" → "25th".
    /// Plurals ("two fifths", "ten seconds") are skipped via word boundaries.
    public static func normalizeOrdinals(_ text: String) -> String {
        let numTok = "(?:\(numberWordPattern)|and|\\d+)"
        let pattern = "\\b(?:\(numTok)[\\s-]+)*(?:\(ordinalWordPattern))\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [],
                                    range: NSRange(location: 0, length: nsText.length))

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let runText = String(result[range])
            if let (value, suffix) = parseOrdinalRun(runText) {
                result.replaceSubrange(range, with: "\(value)\(suffix)")
            }
        }
        return result
    }

    /// Standard-English connector: drop "and" between hundred/thousand/million and a
    /// following number/ordinal word so the run parses as one number.
    /// "one hundred and forty two" → "one hundred forty two" (→ 142).
    /// Leaves "five and ten" and already-digit text ("1100 and 42") untouched.
    public static func stripConnectingAnd(_ text: String) -> String {
        let lookahead = "(?:\(numberWordPattern)|\(ordinalWordPattern))"
        let pattern = "\\b(hundred|thousand|million)\\s+and\\s+(?=\(lookahead)\\b)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let nsText = text as NSString
        return regex.stringByReplacingMatches(
            in: text, options: [],
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: "$1 ")
    }
}
