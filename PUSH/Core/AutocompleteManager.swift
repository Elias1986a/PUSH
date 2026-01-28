import Foundation

/// Orchestrates autocomplete: keystroke monitoring, prediction, overlay display, and text insertion
@MainActor
final class AutocompleteManager: @unchecked Sendable {
    static let shared = AutocompleteManager()

    // MARK: - State

    private(set) var isEnabled = false
    private(set) var currentPrediction = ""

    private let keystrokeMonitor = KeystrokeMonitor.shared
    private let predictionEngine = TextPredictionEngine.shared
    private let overlay = PredictionOverlayController.shared
    private let textInjector = TextInjector.shared

    private init() {}

    private func log(_ message: String) {
        let logPath = "/tmp/push_debug.log"
        let timestamp = Date().ISO8601Format()
        let logMessage = "\(timestamp): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    // MARK: - Public API

    /// Enable autocomplete (loads model if needed)
    func enable() async throws {
        guard !isEnabled else { return }

        // Load model if not already loaded
        if !predictionEngine.isModelLoaded {
            try await predictionEngine.loadDefaultModel()
        }

        // Sync personal context from AppState
        predictionEngine.personalContext = AppState.shared.personalContext

        // Set up keystroke monitor callbacks
        keystrokeMonitor.onPredictionTriggered = { [weak self] context in
            guard let self = self else { return }
            Task { @MainActor in
                await self.generatePrediction(for: context)
            }
        }

        keystrokeMonitor.onTabPressed = { [weak self] in
            self?.acceptNextWord()
        }

        keystrokeMonitor.onBacktickPressed = { [weak self] in
            self?.acceptFullPrediction()
        }

        keystrokeMonitor.onEscapePressed = { [weak self] in
            self?.dismissPrediction()
        }

        // Start monitoring
        keystrokeMonitor.startMonitoring()
        isEnabled = true
        log("AutocompleteManager: ✅ Enabled and monitoring")
    }

    /// Disable autocomplete
    func disable() {
        keystrokeMonitor.stopMonitoring()
        overlay.hide()
        currentPrediction = ""
        isEnabled = false
        print("AutocompleteManager: Disabled")
    }

    /// Accept the next word from the current prediction (Tab key)
    func acceptNextWord() {
        guard !currentPrediction.isEmpty else { return }

        let trimmed = currentPrediction.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)

        guard let firstWord = words.first else { return }

        // Include trailing space if there are more words
        let textToInsert: String
        let remaining: String
        if words.count > 1 {
            textToInsert = String(firstWord) + " "
            remaining = String(words[1])
        } else {
            textToInsert = String(firstWord)
            remaining = ""
        }

        // Inject the word
        textInjector.insertText(textToInsert)

        // Update prediction to show remaining text
        currentPrediction = remaining
        if remaining.isEmpty {
            overlay.hide()
        } else {
            overlay.show(prediction: remaining)
        }

        print("AutocompleteManager: Accepted word: '\(textToInsert)'")
    }

    /// Accept the full prediction (backtick key)
    func acceptFullPrediction() {
        guard !currentPrediction.isEmpty else { return }

        let text = currentPrediction
        overlay.hide()
        currentPrediction = ""

        // Inject the full predicted text
        textInjector.insertText(text)

        // Clear context so next prediction starts fresh from new position
        keystrokeMonitor.clearContext()

        print("AutocompleteManager: Accepted full prediction: '\(text)'")
    }

    /// Dismiss the current prediction (Escape key)
    func dismissPrediction() {
        overlay.hide()
        currentPrediction = ""
    }

    /// Update personal context (called when settings change)
    func updatePersonalContext(_ context: String) {
        predictionEngine.personalContext = context
    }

    // MARK: - Private

    private func generatePrediction(for context: String) async {
        log("AutocompleteManager: Generating prediction for context...")
        let prediction = await predictionEngine.predictNext(context: context)

        guard !prediction.isEmpty else {
            log("AutocompleteManager: No prediction generated")
            overlay.hide()
            currentPrediction = ""
            return
        }

        log("AutocompleteManager: Got prediction: '\(prediction)'")
        currentPrediction = prediction
        overlay.show(prediction: prediction)
    }
}
