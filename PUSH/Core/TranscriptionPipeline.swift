import Foundation
import NaturalLanguage

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
        case .parakeetUnified:
            return try await ParakeetUnifiedEngine.shared.transcribe(audioData: audioData)
        case .parakeetStreaming:
            return try await ParakeetStreamingEngine.shared.transcribe(audioData: audioData)
        case .whisperKit:
            return try await WhisperEngine.shared.transcribe(audioData: audioData)
        case .appleSpeech:
            guard #available(macOS 26, *) else { throw ModelLoaderError.requiresNewerSystem }
            return try await AppleSpeechEngine.shared.transcribe(audioData: audioData)
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

            // Act on spoken self-corrections before formatting, while the
            // markers are still intact — the formatting pipeline rewrites
            // punctuation around exactly the commas these depend on.
            if await MainActor.run(body: { AppState.shared.resolveSelfCorrections }) {
                let beforeCount = filteredText.count
                filteredText = Self.resolveSelfCorrections(filteredText)
                if filteredText.count != beforeCount {
                    // Lengths only — the transcript itself is never logged.
                    PushLogger.log("TranscriptionPipeline: resolved self-correction (\(beforeCount) → \(filteredText.count) chars)")
                }
            }

            // Post-processing pipeline varies by model capability:
            // Models with native punctuation (Parakeet) get a reduced pipeline
            // to avoid overriding their higher-quality formatting.
            var formattedText = Self.postProcess(
                filteredText, hasNativePunctuation: activeModel.hasNativePunctuation)

            // Apple's on-device model, when the user has opted in, *replaces* that
            // chain rather than running after it — see AppleTextCleanup. It returns
            // nil for every failure (unavailable, timeout, implausible output), and
            // the rule-based result computed above is the fallback, so a stalled
            // model can never cost an utterance already spoken.
            if #available(macOS 26, *),
               await MainActor.run(body: { AppState.shared.useAppleCleanup }),
               let cleaned = await AppleTextCleanup.clean(filteredText) {
                formattedText = cleaned
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
    /// Opening punctuation a sentence can start behind, so `. "hello` still
    /// capitalises. Everything else counts as content.
    private static let sentenceStartPassThrough: Set<Character> = ["\"", "'", "\u{201C}", "\u{2018}", "(", "["]

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
                } else if char.isWhitespace || sentenceStartPassThrough.contains(char) {
                    // Transparent: a pending sentence start survives the gap.
                } else {
                    // Any other content — digit, symbol, letter — occupies the
                    // sentence start, so nothing later gets capitalised for it.
                    // Clearing only on letters left the flag armed across digits
                    // and it landed on the next letter it found: "31st" → "31St",
                    // "142 people" → "142 People", "50% of" → "50% Of". The
                    // decimal point in "$2.5 million" re-armed it — "Million".
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

        // "like" is the hard one: it is a filler and an ordinary verb and a
        // comparison and an approximation, so only shapes that cannot be any of
        // the other three are stripped.
        //
        // Left alone on purpose:
        //   verb           "I like it"
        //   comparison     "looks like rain", "like this", "was like a dream"
        //   approximation  "like 30 minutes" — dropping it changes the number's
        //                  meaning from about-thirty to exactly-thirty
        //
        // Comma-bounded filler: "I was, like, going".
        //
        // Both commas go, not just the word. They were only there to bracket
        // the filler, and leaving one behind produced "I was, going" — the
        // filler removed and a comma splice left in its place.
        if let likeRegex = try? NSRegularExpression(pattern: ",\\s*like\\s*,\\s*", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = likeRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        // Sentence-initial: "Like, I don't know" — nothing precedes it to
        // compare to, so it cannot be the comparison sense.
        if let regex = try? NSRegularExpression(
            pattern: "(^|(?<=[.!?])\\s+)like\\s*,\\s*",
            options: .caseInsensitive
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        result = removeFillerLike(result)

        // Remove standalone "um" and "uh" (with surrounding commas/spaces)
        // Patterns: ", um," / ", uh," / "Um, " at start / " um " mid-sentence
        for filler in ["um", "uh"] {
            // Mid-sentence with commas: ", um," — both commas go with it, for
            // the same reason as the filler "like" above.
            if let regex = try? NSRegularExpression(pattern: ",\\s*\(filler)\\s*,\\s*", options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
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

    // MARK: - Spoken self-corrections

    /// Markers that replace what was just said: keep what follows, drop a
    /// comparable span before.
    ///
    /// Every one of these is a phrase, not a word, and that is the whole
    /// design. This function *deletes words the user actually said*, so a
    /// false positive is far worse than a miss — it silently loses meaning and
    /// the user may not notice until later. Bare "sorry", "actually" and
    /// "rather" are the obvious candidates and all three are excluded: "I'm
    /// sorry about that", "I actually like it", "I'd rather go" are ordinary
    /// speech, and there is no reliable way to tell them apart here. They are
    /// exactly the cases to hand to the LLM resolver later, not to guess at.
    static let replacementMarkers = [
        "i mean", "i meant", "no wait", "wait no", "make that", "or rather"
    ]

    /// Markers that abandon the sentence so far and start it again.
    static let restartMarkers = [
        "scratch that", "let me start over", "start over", "delete that"
    ]

    /// Resolve spoken self-corrections: "the red car, I mean the blue car"
    /// becomes "the blue car".
    ///
    /// The span rule for a replacement is that the correction is about as long
    /// as the thing it corrects — so it deletes as many words before the marker
    /// as the replacement has after it. "the red car, I mean the blue car"
    /// replaces with three words, so three come off the front. That is a
    /// heuristic, and it is wrong when someone corrects three words with one;
    /// deciding the span properly is the job the LLM resolver exists for.
    ///
    /// Deletion never crosses a sentence boundary, so a correction can't eat
    /// the sentence before it however the count lands.
    static func resolveSelfCorrections(_ text: String) -> String {
        var result = text
        // Each pass resolves the first marker. The cap stops a pathological
        // transcript from looping; real speech never stacks this many.
        for _ in 0..<8 {
            guard let resolved = resolveFirstSelfCorrection(in: result) else { break }
            result = resolved
        }
        return result
    }

    /// One pass. Returns nil when there is no marker left to resolve.
    private static func resolveFirstSelfCorrection(in text: String) -> String? {
        let lower = text.lowercased()

        var found: (range: Range<String.Index>, isRestart: Bool)?
        for marker in replacementMarkers + restartMarkers {
            guard let r = lower.range(of: marker) else { continue }
            // Word boundaries, so "I meant" doesn't fire inside "I meantime".
            let startsClean = r.lowerBound == lower.startIndex
                || !lower[lower.index(before: r.lowerBound)].isLetter
            let endsClean = r.upperBound == lower.endIndex
                || !lower[r.upperBound].isLetter
            guard startsClean, endsClean else { continue }
            if found == nil || r.lowerBound < found!.range.lowerBound {
                found = (r, restartMarkers.contains(marker))
            }
        }
        guard let marker = found else { return nil }

        let before = String(text[..<marker.range.lowerBound])
        let after = String(text[marker.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing to correct with — drop the dangling marker and keep the text.
        if after.isEmpty { return trimDangling(before) }

        let sentenceStart = startOfLastSentence(in: before)
        let head = String(before[..<sentenceStart])
        let clause = String(before[sentenceStart...])

        if marker.isRestart {
            return join(head, after)
        }

        // Replacement: drop as many words as the correction supplies, capped at
        // the clause so the previous sentence is never touched.
        let replacementLength = after
            .prefix { $0 != "." && $0 != "!" && $0 != "?" }
            .split(whereSeparator: \.isWhitespace)
            .count
        var kept = clause.split(whereSeparator: \.isWhitespace).map(String.init)
        kept.removeLast(min(replacementLength, kept.count))

        return join(head + kept.joined(separator: " "), after)
    }

    /// Index just past the previous sentence's terminator, or the start.
    private static func startOfLastSentence(in text: String) -> String.Index {
        guard let terminator = text.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" })
        else { return text.startIndex }
        return text.index(after: terminator)
    }

    private static func join(_ left: String, _ right: String) -> String {
        let head = trimDangling(left)
        if head.isEmpty { return right }
        return head + " " + right
    }

    /// Strip the whitespace and the comma left hanging by a removed span, so
    /// "the red car, " doesn't become "the red car ,".
    private static func trimDangling(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last == "," || last == ";" || last == "-" {
            t.removeLast()
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    // MARK: - Filler "like"

    /// Words after which a preposition-tagged "like" is filler rather than a
    /// comparison. Negations, conjunctions and subject pronouns cannot be the
    /// left side of a comparison — "he like lives here" has nothing being
    /// compared — whereas a noun or a comparison verb can: "people like us",
    /// "looks like rain".
    private static let fillerLikePredecessors: Set<String> = [
        "not", "never", "and", "but", "so", "or",
        "i", "he", "she", "it", "they", "we", "you"
    ]

    /// Strip filler "like" using the on-device part-of-speech tagger.
    ///
    /// String patterns alone cannot do this. Measured against the tagger, the
    /// senses are not separable by the tag on "like" by itself — filler and
    /// comparison both come back `Preposition` — and they are not separable by
    /// the neighbouring words either, because "I like pizza" and "he like
    /// lives" have the same shape. It takes both: the tag rules out the verb,
    /// the neighbours rule out the comparison.
    ///
    /// Without the tag, a rule matching pronoun + "like" turns "I like pizza"
    /// into "I pizza". That is the whole reason this is not a regex.
    static func removeFillerLike(_ text: String) -> String {
        guard text.range(of: "like", options: .caseInsensitive) != nil else { return text }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        // Collected first, applied last-to-first, so earlier ranges stay valid.
        var doomed: [Range<String.Index>] = []
        var previousWord = ""

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            let word = text[range].lowercased()
            defer { previousWord = word }
            guard word == "like" else { return true }

            switch tag {
            case .verb:
                // "I like it", "would like a coffee", and — because the tagger
                // labels it so — "do it like this". Never removed: this is the
                // case where a wrong guess destroys the sentence.
                return true

            case .interjection:
                // The tagger's own filler reading. Kept only before a number,
                // where it means "about": dropping it in "in like 30 minutes"
                // would turn an estimate into a precise claim.
                if !nextWordIsNumber(after: range, in: text) {
                    doomed.append(range)
                }

            case .preposition:
                // Ambiguous: both "looks like rain" and "not like irate". The
                // preceding word decides.
                if Self.fillerLikePredecessors.contains(previousWord),
                   !nextWordIsNumber(after: range, in: text) {
                    doomed.append(range)
                }

            default:
                break
            }
            return true
        }

        guard !doomed.isEmpty else { return text }

        var result = text
        for range in doomed.reversed() {
            result.replaceSubrange(range, with: "")
        }
        return result
    }

    private static func nextWordIsNumber(after range: Range<String.Index>, in text: String) -> Bool {
        let rest = text[range.upperBound...]
        guard let next = rest.split(whereSeparator: \.isWhitespace).first else { return false }
        return next.first?.isNumber ?? false
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

        // "50 dollars" → "$50". The number must be matched whole: this pass runs
        // *after* comma-grouping, and a bare \d+ matched only the last group of
        // "5,000,000 dollars", which turned it into "5,000,$000". A trailing
        // magnitude word is part of the amount too — "5 million dollars" is
        // "$5 million", not "$5 million dollars".
        let amount = "\\d[\\d,]*(?:\\.\\d+)?"
        let magnitude = "(?:\\s+(?:hundred|thousand|million))?"
        if let regex = try? NSRegularExpression(pattern: "(?<![\\d.,])(\(amount)\(magnitude))\\s+dollars?\\b",
                                                options: .caseInsensitive) {
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

    // MARK: - Post-processing chain

    /// The whole post-processing chain, in order. Extracted from the transcription
    /// path so the passes can be tested *in composition* — the number bugs users
    /// actually hit have been interactions between passes (comma-grouping running
    /// before the dollar rule, decimal dictation running before magnitude words),
    /// not faults in any single pass. Testing them one at a time hides that.
    ///
    /// `hasNativePunctuation` (Parakeet) skips the punctuation/capitalisation
    /// passes so we don't override the model's own, better, formatting.
    static func postProcess(_ text: String, hasNativePunctuation: Bool) -> String {
        var out = normalizeCause(text)
        out = removeFillerWords(out)
        out = removeStutteredWords(out)
        out = stripConnectingAnd(out)
        out = normalizeOrdinals(out)
        out = normalizeDecimalDictation(out)
        out = normalizeNumberWords(out)
        out = groupThousands(out)
        if !hasNativePunctuation {
            out = fixTrailingComma(out)
            out = ensureEndingPunctuation(out)
            out = fixQuestionMarks(out)
        }
        out = smartSymbols(out)
        if !hasNativePunctuation {
            out = fixCapitalization(out)
            out = capitalizeI(out)
        }
        return out
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
    static func isBareMagnitudeRun(_ run: String) -> Bool {
        let words = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        return !words.isEmpty && words.allSatisfy { magnitudeWords.contains($0) }
    }

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

    /// Parse the fractional side of a dictated decimal into its digits.
    /// "one four" is 14, not 5 — pi is dictated "three point one four", and summing
    /// the run gave "3.5". But "twenty five" is 25, not "205". The rule that splits
    /// them: a run of nothing but single digits concatenates, anything else parses
    /// arithmetically.
    static func parseDecimalFraction(_ run: String) -> String? {
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
    static func normalizeDecimalDictation(_ text: String) -> String {
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
    static func insertThousandsSeparators(_ digits: String) -> String {
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
    static func formatSpokenNumber(_ value: Int) -> String {
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
    static func parseSpokenYear(_ run: String) -> Int? {
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
    static func groupThousands(_ text: String) -> String {
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
