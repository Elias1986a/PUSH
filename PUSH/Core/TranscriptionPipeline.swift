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

            // Check for empty, [BLANK_AUDIO], bracketed text, or silence markers
            var lowerText = filteredText.lowercased()
            if filteredText.isEmpty ||
               lowerText.contains("blank_audio") ||
               lowerText.contains("blank audio") ||
               lowerText.contains("silence") ||
               filteredText.hasPrefix("(") && filteredText.hasSuffix(")") ||
               filteredText.hasPrefix("[") && filteredText.hasSuffix("]") {
                PushLogger.log("TranscriptionPipeline: No speech detected (empty or blank audio)")
                PushLogger.log("TranscriptionPipeline: No speech detected")
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

            // Whisper Small provides excellent formatting, no need for additional processing
            let formattedText = filteredText

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
}
