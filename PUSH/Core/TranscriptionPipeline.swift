import Foundation

/// Orchestrates the transcription pipeline: audio → Whisper → Qwen → text injection
actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private init() {}

    // MARK: - Hallucination Filters

    /// Exact-match hallucination phrases (Whisper outputs these on silence/ambient noise)
    private static let hallucinationPhrases: Set<String> = [
        "subscribe", "like and subscribe",
        "see you next time", "bye", "goodbye",
        "you", "the end", "the end."
    ]

    /// Prefix-match hallucinations (catch "thank you", "thank you so much", "thanks for watching", etc.)
    private static let hallucinationPrefixes = [
        "thank you", "thanks for"
    ]

    // MARK: - Public API

    /// Route audio to the engine backing `model`. Shared by the main pipeline
    /// and the wake word listener so both always use the loaded engine.
    static func transcribe(audioData: Data, using model: AppState.WhisperModel) async throws -> String {
        switch model.engineType {
        case .moonshine:
            return try await MoonshineEngine.shared.transcribe(audioData: audioData)
        case .parakeet:
            return try await ParakeetEngine.shared.transcribe(audioData: audioData)
        case .whisperKit:
            return try await WhisperEngine.shared.transcribe(audioData: audioData)
        }
    }

    /// Process audio data through the full pipeline
    func process(audioData: Data) async {
        do {
            PushLogger.log("TranscriptionPipeline: Starting transcription, audio size: \(audioData.count) bytes")
            // Step 1: Transcribe with the active (loaded) engine — the selected
            // preference may still be downloading; ModelLoader swaps activeModel
            // only once the new model is ready.
            let activeModel = await MainActor.run { AppState.shared.activeModel }
            PushLogger.log("TranscriptionPipeline: Using \(activeModel.engineType) engine...")
            let rawText = try await Self.transcribe(audioData: audioData, using: activeModel)

            // Filter out empty results and Whisper's blank audio markers
            var filteredText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for empty, [BLANK_AUDIO], bracketed text, silence markers,
            // and common Whisper hallucinations on silence/ambient noise
            var lowerText = filteredText.lowercased()
            if filteredText.isEmpty ||
               lowerText.contains("blank_audio") ||
               lowerText.contains("blank audio") ||
               lowerText.contains("silence") ||
               Self.hallucinationPhrases.contains(lowerText) ||
               Self.hallucinationPrefixes.contains(where: { lowerText.hasPrefix($0) }) ||
               filteredText.hasPrefix("(") && filteredText.hasSuffix(")") ||
               filteredText.hasPrefix("[") && filteredText.hasSuffix("]") {
                PushLogger.log("TranscriptionPipeline: No speech detected (empty, blank, or hallucination)")
                return
            }

            // Strip "beep" from the start of transcription (microphone picks up the chirp sound effect)
            // Handle variations: "Beep", "beep,", "Beep.", "beep ", "(beeping)", "[beeping]", etc.
            let beepPatterns = [
                #/^\(beep(ing)?\)[,.\s]*/#,      // (beep) or (beeping)
                #/^\[beep(ing)?\][,.\s]*/#,      // [beep] or [beeping]
                #/^beep(ing)?[,.\s]*/#           // beep or beeping
            ]
            for pattern in beepPatterns {
                if let match = try? pattern.ignoresCase().prefixMatch(in: filteredText) {
                    filteredText = String(filteredText[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    lowerText = filteredText.lowercased()
                    PushLogger.log("TranscriptionPipeline: Stripped beep prefix from transcription")
                    break
                }
            }

            // If only "beep" was transcribed (nothing left after stripping), treat as no speech
            if filteredText.isEmpty || lowerText == "beep" || lowerText == "beeping" {
                PushLogger.log("TranscriptionPipeline: No speech detected (only beep sound)")
                return
            }

            // Strip wake word from the start of transcription if enabled
            let (wakeWordEnabled, wakeWord) = await MainActor.run {
                (AppState.shared.wakeWordEnabled, AppState.shared.wakeWord)
            }
            if wakeWordEnabled && !wakeWord.isEmpty {
                // Create pattern to match wake word at start (case insensitive)
                // Handle variations: "push", "Push,", "push.", "push " etc.
                let escapedWakeWord = NSRegularExpression.escapedPattern(for: wakeWord)
                if let regex = try? NSRegularExpression(pattern: "^" + escapedWakeWord + "[,.:!?\\s]*", options: .caseInsensitive) {
                    let range = NSRange(filteredText.startIndex..., in: filteredText)
                    if let match = regex.firstMatch(in: filteredText, options: [], range: range) {
                        let matchRange = Range(match.range, in: filteredText)!
                        filteredText = String(filteredText[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        lowerText = filteredText.lowercased()
                        PushLogger.log("TranscriptionPipeline: Stripped wake word from transcription")
                    }
                }

                // If only wake word was transcribed (nothing left after stripping), treat as no speech
                if filteredText.isEmpty || lowerText == wakeWord.lowercased() {
                    PushLogger.log("TranscriptionPipeline: No speech detected (only wake word)")
                    return
                }
            }

            // Avoid logging raw transcription text to protect user privacy.
            PushLogger.log("TranscriptionPipeline: Whisper transcription received (\(filteredText.count) chars)")

            // Apply user-defined dictionary corrections (e.g. names Whisper consistently mishears).
            // `.always` entries replace unconditionally; `.contextual` entries are gated so
            // homophones (the tool "hammer" vs. the person "Hamer") aren't corrupted.
            let corrections = await MainActor.run { CorrectionsStore.shared.corrections }
            filteredText = await CorrectionsStore.applyContextAware(corrections, to: filteredText)

            // Post-processing pipeline varies by model capability:
            // Models with native punctuation (Parakeet) get a reduced pipeline
            // to avoid overriding their higher-quality formatting.
            var formattedText: String
            if activeModel.hasNativePunctuation {
                // Reduced pipeline: filler/stutter removal, number normalization, smart symbols
                formattedText = Self.smartSymbols(
                    Self.normalizeNumberWords(
                        Self.normalizeDecimalDictation(
                            Self.normalizeOrdinals(
                                Self.stripConnectingAnd(
                                    Self.removeStutteredWords(
                                        Self.removeFillerWords(Self.normalizeCause(filteredText))
                                    )
                                )
                            )
                        )
                    )
                )
            } else {
                // Full pipeline for Whisper/Moonshine models
                formattedText = Self.capitalizeI(
                    Self.fixCapitalization(
                        Self.smartSymbols(
                            Self.fixQuestionMarks(
                                Self.ensureEndingPunctuation(
                                    Self.fixTrailingComma(
                                        Self.normalizeNumberWords(
                                            Self.normalizeDecimalDictation(
                                                Self.normalizeOrdinals(
                                                    Self.stripConnectingAnd(
                                                        Self.removeStutteredWords(
                                                            Self.removeFillerWords(Self.normalizeCause(filteredText))
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            }

            // Typographic preference — off by request via Settings → General.
            if await MainActor.run(body: { AppState.shared.doubleSpaceAfterSentence }) {
                formattedText = Self.doubleSpaceAfterPeriods(formattedText)
            }

            // Step 2: Inject into active text field
            PushLogger.log("TranscriptionPipeline: Injecting text...")
            let textToInject = formattedText
            await MainActor.run {
                TextInjector.shared.insertText(textToInject)
            }

            PushLogger.log("TranscriptionPipeline: ✅ Text injected successfully")

        } catch {
            PushLogger.log("TranscriptionPipeline: ❌ ERROR - \(error)")
            await MainActor.run {
                AppState.shared.statusMessage = "Error: \(error.localizedDescription)"
                NotificationManager.shared.showTranscriptionError()
            }
        }
    }

    // MARK: - Text Post-Processing

    /// Capitalize the first letter of the text and the first letter after sentence-ending punctuation
    static func fixCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "?" || char == "!" {
                    capitalizeNext = true
                } else if char.isLetter {
                    capitalizeNext = false
                }
            }
        }

        return result
    }

    /// Capitalize standalone "i" → "I" (the pronoun, not inside words)
    static func capitalizeI(_ text: String) -> String {
        // Match standalone "i" surrounded by word boundaries
        guard let regex = try? NSRegularExpression(pattern: "\\bi\\b", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "I")
    }

    /// Add double space after sentence-ending punctuation (. ? !).
    /// Note: this can't distinguish abbreviations ("Dr. Smith" also gets two
    /// spaces), which is part of why it's user-toggleable.
    static func doubleSpaceAfterPeriods(_ text: String) -> String {
        var result = text
        // Replace single space after sentence-ending punctuation with double space
        for punct in [".", "?", "!"] {
            result = result.replacingOccurrences(of: "\(punct) ", with: "\(punct)  ")
            // Fix triple+ spaces back to double (in case already double-spaced)
            while result.contains("\(punct)   ") {
                result = result.replacingOccurrences(of: "\(punct)   ", with: "\(punct)  ")
            }
        }
        return result
    }

    /// Remove filler words: "um", "uh" always; "like" only when comma-bounded filler
    static func removeFillerWords(_ text: String) -> String {
        var result = text

        // Remove ", like," (filler usage, e.g. "I was, like, going")
        if let likeRegex = try? NSRegularExpression(pattern: ",\\s*like\\s*,", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = likeRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: ",")
        }

        // Remove standalone "um" and "uh" (with surrounding commas/spaces)
        // Patterns: ", um," / ", uh," / "Um, " at start / " um " mid-sentence
        for filler in ["um", "uh"] {
            // Mid-sentence with commas: ", um,"
            if let regex = try? NSRegularExpression(pattern: ",\\s*\(filler)\\s*,", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: ",")
            }
            // Start of text: "Um, " or "Uh, "
            if let regex = try? NSRegularExpression(pattern: "^\\s*\(filler)\\s*,?\\s*", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
            // Standalone mid-sentence: " um " (no commas)
            if let regex = try? NSRegularExpression(pattern: "\\s+\(filler)\\s+", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
            }
        }

        // Clean up any double spaces left behind
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove stuttered/duplicate consecutive words: "the the" → "the", "I I" → "I"
    static func removeStutteredWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\\w+)\\s+\\1\\b",
            options: .caseInsensitive
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    /// Fix question marks: sentences starting with question words should end with ?
    static func fixQuestionMarks(_ text: String) -> String {
        let questionWords: Set<String> = [
            "who", "what", "where", "when", "why", "how",
            "is", "are", "am", "was", "were",
            "do", "does", "did",
            "can", "could", "would", "should", "shall", "will",
            "have", "has", "had",
            "isn't", "aren't", "don't", "doesn't", "didn't",
            "won't", "wouldn't", "couldn't", "shouldn't",
            "isn\u{2019}t", "aren\u{2019}t", "don\u{2019}t", "doesn\u{2019}t", "didn\u{2019}t",
            "won\u{2019}t", "wouldn\u{2019}t", "couldn\u{2019}t", "shouldn\u{2019}t"
        ]

        // Split into sentences on . or ? or !
        // Process each sentence: if it starts with a question word and ends with ., flip to ?
        var result = ""
        var current = ""

        for char in text {
            current.append(char)
            if char == "." || char == "?" || char == "!" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstWord = trimmed.split(separator: " ").first.map { String($0).lowercased() } ?? ""

                if char == "." && questionWords.contains(firstWord) {
                    // Replace trailing period with question mark
                    let idx = current.lastIndex(of: ".")!
                    current.replaceSubrange(idx...idx, with: "?")
                }

                result.append(current)
                current = ""
            }
        }
        // Append any remaining text (no trailing punctuation)
        result.append(current)

        return result
    }

    /// Replace trailing comma with a period (model sometimes leaves a dangling comma)
    static func fixTrailingComma(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(",") {
            result = String(result.dropLast()) + "."
        }
        return result
    }

    /// Add a period at the end if there's no ending punctuation
    static func ensureEndingPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let lastChar = trimmed.last!
        if lastChar == "." || lastChar == "?" || lastChar == "!" {
            return text
        }
        return trimmed + "."
    }

    /// Smart symbol replacement: "percent" → "%", "dollar" → "$", "at sign" → "@"
    static func smartSymbols(_ text: String) -> String {
        var result = text

        // Number + "percent" → number + "%"  (e.g. "50 percent" → "50%")
        if let regex = try? NSRegularExpression(pattern: "(\\d)\\s+percent\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1%")
        }

        // "dollar" / "dollars" before or after numbers
        // "$50" pattern: "50 dollars" → "$50", "50 dollar" → "$50"
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s+dollars?\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\\$$1")
        }

        // "at sign" or "at symbol" → "@"
        if let regex = try? NSRegularExpression(pattern: "\\bat\\s+sign\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "@")
        }

        // "hashtag" or "hash sign" → "#"
        if let regex = try? NSRegularExpression(pattern: "\\bhash\\s*tag\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "#")
        }

        // "ampersand" → "&"
        if let regex = try? NSRegularExpression(pattern: "\\bampersand\\b", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "&")
        }

        return result
    }

    /// Strip the leading apostrophe Whisper adds to the contraction of "because":
    /// "'cause" → "cause" (handles straight and curly apostrophes, preserves casing).
    static func normalizeCause(_ text: String) -> String {
        // (^|non-word) + apostrophe + "cause" word → drop the apostrophe, keep the boundary and word.
        guard let regex = try? NSRegularExpression(
            pattern: "(^|[^A-Za-z'\u{2019}])['\u{2019}](causes?)\\b",
            options: .caseInsensitive
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1$2")
    }

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

    /// Parse a contiguous run of number words ("twenty five", "one hundred five") into an Int.
    /// Returns nil if any token isn't recognized. `allowOh` enables "oh" → 0 for decimal contexts.
    static func parseNumberRun(_ run: String, allowOh: Bool = false) -> Int? {
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

    /// Rewrite "X point Y [point Z]" dictation as "X.Y[.Z]" (versions, decimals).
    /// "four point zero point two" → "4.0.2"; "ten point five" → "10.5".
    static func normalizeDecimalDictation(_ text: String) -> String {
        let word = decimalWordPattern
        let chunk = "(?:\(word))(?:[\\s-]+(?:\(word)))*"
        let pattern = "\\b\(chunk)(?:\\s+point\\s+\(chunk))+\\b"

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
            for piece in pieces {
                if let v = parseNumberRun(piece, allowOh: true) {
                    digits.append(String(v))
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
    static func normalizeNumberWords(_ text: String) -> String {
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
            if let value = parseNumberRun(runText), value >= 10 {
                result.replaceSubrange(range, with: String(value))
            }
        }
        return result
    }

    /// "st"/"nd"/"rd"/"th" suffix for an ordinal value (11–13 are always "th").
    static func ordinalSuffix(_ n: Int) -> String {
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
    static func parseOrdinalRun(_ run: String) -> (value: Int, suffix: String)? {
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
    static func normalizeOrdinals(_ text: String) -> String {
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
    static func stripConnectingAnd(_ text: String) -> String {
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
