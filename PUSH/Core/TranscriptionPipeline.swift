import Foundation

/// Orchestrates the transcription pipeline: audio → Whisper → Qwen → text injection
actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private init() {}

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
            let hallucinationPhrases: Set<String> = [
                "thank you", "thank you.", "thanks for watching",
                "thanks for watching.", "subscribe", "like and subscribe",
                "see you next time", "bye", "goodbye",
                "you", "the end", "the end."
            ]
            if filteredText.isEmpty ||
               lowerText.contains("blank_audio") ||
               lowerText.contains("blank audio") ||
               lowerText.contains("silence") ||
               hallucinationPhrases.contains(lowerText) ||
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
                PushLogger.log("TranscriptionPipeline: No speech detected")
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
                    PushLogger.log("TranscriptionPipeline: No speech detected")
                    return
                }
            }

            // Avoid logging raw transcription text to protect user privacy.
            PushLogger.log("TranscriptionPipeline: Whisper transcription received (\(filteredText.count) chars)")
            PushLogger.log("TranscriptionPipeline: Whisper transcription received (\(filteredText.count) chars)")

            // Post-processing: capitalization, "I" pronoun, double space after periods
            let formattedText = Self.doubleSpaceAfterPeriods(
                Self.capitalizeI(
                    Self.fixCapitalization(filteredText)
                )
            )

            // Step 2: Inject into active text field
            PushLogger.log("TranscriptionPipeline: Injecting text...")
            await MainActor.run {
                TextInjector.shared.insertText(formattedText)
            }

            PushLogger.log("TranscriptionPipeline: ✅ Text injected successfully")
            PushLogger.log("TranscriptionPipeline: Text injected successfully")

        } catch {
            PushLogger.log("TranscriptionPipeline: ❌ ERROR - \(error)")
            PushLogger.log("TranscriptionPipeline: Error - \(error)")
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
}
