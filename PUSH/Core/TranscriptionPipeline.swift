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

    /// Process audio data through the full pipeline
    func process(audioData: Data) async {
        do {
            PushLogger.log("TranscriptionPipeline: Starting transcription, audio size: \(audioData.count) bytes")
            // Step 1: Transcribe with the selected engine
            let selectedModel = await MainActor.run { AppState.shared.selectedWhisperModel }
            let rawText: String
            if selectedModel.isMoonshine {
                PushLogger.log("TranscriptionPipeline: Using Moonshine engine...")
                rawText = try await MoonshineEngine.shared.transcribe(audioData: audioData)
            } else {
                PushLogger.log("TranscriptionPipeline: Using WhisperKit engine...")
                rawText = try await WhisperEngine.shared.transcribe(audioData: audioData)
            }

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

            // Post-processing pipeline (order matters):
            // 1. Remove filler words first (before capitalization fixes them in place)
            // 2. Remove stuttered/duplicate words
            // 3. Fix trailing comma
            // 4. Ensure ending punctuation
            // 5. Fix question marks (before capitalization)
            // 6. Smart symbols (%, $, @)
            // 7. Capitalize after punctuation
            // 8. Capitalize standalone "I"
            // 9. Double space after periods (last, so spacing is clean)
            let formattedText = Self.doubleSpaceAfterPeriods(
                Self.capitalizeI(
                    Self.fixCapitalization(
                        Self.smartSymbols(
                            Self.fixQuestionMarks(
                                Self.ensureEndingPunctuation(
                                    Self.fixTrailingComma(
                                        Self.removeStutteredWords(
                                            Self.removeFillerWords(filteredText)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )

            // Step 2: Inject into active text field
            PushLogger.log("TranscriptionPipeline: Injecting text...")
            await MainActor.run {
                TextInjector.shared.insertText(formattedText)
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
    private static func fixCapitalization(_ text: String) -> String {
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
    private static func capitalizeI(_ text: String) -> String {
        // Match standalone "i" surrounded by word boundaries
        guard let regex = try? NSRegularExpression(pattern: "\\bi\\b", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "I")
    }

    /// Add double space after sentence-ending punctuation (. ? !)
    private static func doubleSpaceAfterPeriods(_ text: String) -> String {
        var result = text
        // Replace single space after sentence-ending punctuation with double space
        // But don't touch ellipsis (...) or abbreviations like "Dr." followed by a name
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
    private static func removeFillerWords(_ text: String) -> String {
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
    private static func removeStutteredWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\\w+)\\s+\\1\\b",
            options: .caseInsensitive
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    /// Fix question marks: sentences starting with question words should end with ?
    private static func fixQuestionMarks(_ text: String) -> String {
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
    private static func fixTrailingComma(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(",") {
            result = String(result.dropLast()) + "."
        }
        return result
    }

    /// Add a period at the end if there's no ending punctuation
    private static func ensureEndingPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let lastChar = trimmed.last!
        if lastChar == "." || lastChar == "?" || lastChar == "!" {
            return text
        }
        return trimmed + "."
    }

    /// Smart symbol replacement: "percent" → "%", "dollar" → "$", "at sign" → "@"
    private static func smartSymbols(_ text: String) -> String {
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
}
