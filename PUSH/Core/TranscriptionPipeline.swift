import Foundation

/// Orchestrates the transcription pipeline: audio → Whisper → Qwen → text injection
actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private init() {}

    // MARK: - Public API

    private func log(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    /// Process audio data through the full pipeline
    func process(audioData: Data) async {
        do {
            log("TranscriptionPipeline: Starting Whisper transcription, audio size: \(audioData.count) bytes")
            // Step 1: Transcribe with Whisper
            print("TranscriptionPipeline: Starting Whisper transcription...")
            let rawText = try await WhisperEngine.shared.transcribe(audioData: audioData)

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
                log("TranscriptionPipeline: No speech detected (empty or blank audio): '\(filteredText)'")
                print("TranscriptionPipeline: No speech detected")
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
                    log("TranscriptionPipeline: Stripped beep prefix from transcription")
                    break
                }
            }

            // If only "beep" was transcribed (nothing left after stripping), treat as no speech
            if filteredText.isEmpty || lowerText == "beep" || lowerText == "beeping" {
                log("TranscriptionPipeline: No speech detected (only beep sound): '\(rawText)'")
                print("TranscriptionPipeline: No speech detected")
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
                        log("TranscriptionPipeline: Stripped wake word '\(wakeWord)' from transcription")
                    }
                }

                // If only wake word was transcribed (nothing left after stripping), treat as no speech
                if filteredText.isEmpty || lowerText == wakeWord.lowercased() {
                    log("TranscriptionPipeline: No speech detected (only wake word): '\(rawText)'")
                    print("TranscriptionPipeline: No speech detected")
                    return
                }
            }

            log("TranscriptionPipeline: Raw text from Whisper: '\(filteredText)'")
            print("TranscriptionPipeline: Raw text: \(filteredText)")

            // Whisper Small provides excellent formatting, no need for additional processing
            let formattedText = filteredText

            // Step 2: Inject into active text field
            log("TranscriptionPipeline: Injecting text...")
            await MainActor.run {
                TextInjector.shared.insertText(formattedText)
            }

            log("TranscriptionPipeline: ✅ Text injected successfully")
            print("TranscriptionPipeline: Text injected successfully")

        } catch {
            log("TranscriptionPipeline: ❌ ERROR - \(error)")
            print("TranscriptionPipeline: Error - \(error)")
            await MainActor.run {
                AppState.shared.statusMessage = "Error: \(error.localizedDescription)"
                NotificationManager.shared.showTranscriptionError()
            }
        }
    }
}
