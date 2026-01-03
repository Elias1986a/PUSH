import SwiftUI
import Combine

/// Shared application state
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKeys {
        static let selectedWhisperModel = "selectedWhisperModel"
    }

    // MARK: - Published State

    @Published var isListening: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var isProcessing: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var statusMessage: String = "Ready"

    @Published var selectedWhisperModel: WhisperModel = .small {
        didSet {
            UserDefaults.standard.set(selectedWhisperModel.rawValue, forKey: UserDefaultsKeys.selectedWhisperModel)
        }
    }

    @Published var startAtLogin: Bool = false
    @Published var hotkeyEnabled: Bool = true

    // MARK: - Model Enums

    enum WhisperModel: String, CaseIterable, Identifiable {
        case tiny = "ggml-tiny.en"
        case base = "ggml-base.en"
        case small = "ggml-small.en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tiny: return "Whisper Tiny (75 MB)"
            case .base: return "Whisper Base (150 MB)"
            case .small: return "Whisper Small (500 MB) - Recommended"
            }
        }

        var downloadURL: URL {
            let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
            return URL(string: "\(base)/\(rawValue).bin")!
        }

        var fileSize: Int64 {
            switch self {
            case .tiny: return 75_000_000
            case .base: return 150_000_000
            case .small: return 500_000_000
            }
        }
    }

    // MARK: - Private

    private init() {
        // Load saved Whisper model from UserDefaults
        if let savedModel = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedWhisperModel),
           let model = WhisperModel(rawValue: savedModel) {
            self.selectedWhisperModel = model
        }
    }

    private func notifyStateChange() {
        NotificationCenter.default.post(name: .appStateDidChange, object: nil)
    }
}
