import Foundation

/// Orchestrates the transcription pipeline: audio → Whisper → Qwen → text injection
actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private init() {}

    // MARK: - Public API

    /// Process audio data through the full pipeline
    func process(audioData: Data) async {
        do {
            // Step 1: Transcribe with Whisper
            print("TranscriptionPipeline: Starting Whisper transcription...")
            let rawText = try await WhisperEngine.shared.transcribe(audioData: audioData)

            guard !rawText.isEmpty else {
                print("TranscriptionPipeline: No speech detected")
                return
            }

            print("TranscriptionPipeline: Raw text: \(rawText)")

            // Step 2: Format with Qwen
            print("TranscriptionPipeline: Starting Qwen formatting...")
            let formattedText = try await QwenEngine.shared.format(text: rawText)

            print("TranscriptionPipeline: Formatted text: \(formattedText)")

            // Step 3: Inject into active text field
            await MainActor.run {
                TextInjector.shared.insertText(formattedText)
            }

            print("TranscriptionPipeline: Text injected successfully")

        } catch {
            print("TranscriptionPipeline: Error - \(error)")
            await MainActor.run {
                AppState.shared.statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}
