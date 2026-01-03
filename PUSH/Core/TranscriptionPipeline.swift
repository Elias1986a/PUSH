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
            let filteredText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for empty, [BLANK_AUDIO], bracketed text, or silence markers
            if filteredText.isEmpty ||
               filteredText == "[BLANK_AUDIO]" ||
               filteredText.lowercased().contains("silence") ||
               filteredText.hasPrefix("(") && filteredText.hasSuffix(")") ||
               filteredText.hasPrefix("[") && filteredText.hasSuffix("]") {
                log("TranscriptionPipeline: No speech detected (empty or blank audio): '\(filteredText)'")
                print("TranscriptionPipeline: No speech detected")
                return
            }

            log("TranscriptionPipeline: Raw text from Whisper: '\(rawText)'")
            print("TranscriptionPipeline: Raw text: \(rawText)")

            // Step 2: Format with Qwen (TEMPORARILY DISABLED - Qwen model not loading)
            log("TranscriptionPipeline: Skipping Qwen formatting (using raw Whisper text)")
            let formattedText = rawText
            // TODO: Fix Qwen model loading
            // let formattedText = try await QwenEngine.shared.format(text: rawText)

            log("TranscriptionPipeline: Text to inject: '\(formattedText)'")
            print("TranscriptionPipeline: Text to inject: \(formattedText)")

            // Step 3: Inject into active text field
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
            }
        }
    }
}
