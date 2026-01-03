import SwiftUI
import Combine

/// Shared application state
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published State

    @Published var isListening: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var isProcessing: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var statusMessage: String = "Ready"

    @Published var selectedWhisperModel: WhisperModel = .base
    @Published var selectedQwenModel: QwenModel = .qwen3_1_7B

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
            case .base: return "Whisper Base (150 MB) - Recommended"
            case .small: return "Whisper Small (500 MB)"
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

    enum QwenModel: String, CaseIterable, Identifiable {
        case qwen3_0_6B = "qwen3-0.6b-q4_k_m"
        case qwen3_1_7B = "qwen3-1.7b-q4_k_m"
        case qwen3_4B = "qwen3-4b-q4_k_m"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .qwen3_0_6B: return "Qwen 3 0.6B (400 MB)"
            case .qwen3_1_7B: return "Qwen 3 1.7B (1.2 GB) - Recommended"
            case .qwen3_4B: return "Qwen 3 4B (2.5 GB)"
            }
        }

        var downloadURL: URL {
            // These URLs would need to be updated with actual HuggingFace paths
            let base = "https://huggingface.co/Qwen"
            return URL(string: "\(base)/\(rawValue).gguf")!
        }

        var fileSize: Int64 {
            switch self {
            case .qwen3_0_6B: return 400_000_000
            case .qwen3_1_7B: return 1_200_000_000
            case .qwen3_4B: return 2_500_000_000
            }
        }
    }

    // MARK: - Private

    private init() {}

    private func notifyStateChange() {
        NotificationCenter.default.post(name: .appStateDidChange, object: nil)
    }
}
