import SwiftUI
import Combine

/// Shared application state
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKeys {
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedHotkey = "selectedHotkey"
        static let playSoundOnStart = "playSoundOnStart"
        static let wakeWordEnabled = "wakeWordEnabled"
        static let wakeWord = "wakeWord"
    }

    // MARK: - Published State

    @Published var isListening: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var isProcessing: Bool = false {
        didSet { notifyStateChange() }
    }

    @Published var isModelReady: Bool = false {
        didSet { notifyStateChange() }
    }

    /// True while background shader warmup runs after the model is loaded. The
    /// app is already usable (isModelReady == true); this only drives the
    /// "Warming up…" indicator so the user knows first-use may be slightly slower.
    @Published var isWarmingUp: Bool = false {
        didSet { notifyStateChange() }
    }

    /// True when no model is serving at all (launch load failed, or the active
    /// model's files were deleted). Drives the pill's "Model unavailable" state.
    @Published var modelUnavailable: Bool = false {
        didSet { notifyStateChange() }
    }

    /// The model actually loaded and serving transcriptions. Differs from
    /// `selectedWhisperModel` (the persisted preference) while a newly selected
    /// model downloads/loads — dictation keeps using this one until the swap.
    @Published var activeModel: WhisperModel = .small

    @Published var statusMessage: String = "Ready"

    @Published var selectedWhisperModel: WhisperModel = .small {
        didSet {
            UserDefaults.standard.set(selectedWhisperModel.rawValue, forKey: UserDefaultsKeys.selectedWhisperModel)
        }
    }

    @Published var hotkeyEnabled: Bool = true

    @Published var selectedHotkey: Hotkey = .rightOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey.rawValue, forKey: UserDefaultsKeys.selectedHotkey)
        }
    }

    @Published var playSoundOnStart: Bool = false {
        didSet {
            UserDefaults.standard.set(playSoundOnStart, forKey: UserDefaultsKeys.playSoundOnStart)
        }
    }

    @Published var wakeWordEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(wakeWordEnabled, forKey: UserDefaultsKeys.wakeWordEnabled)
        }
    }

    @Published var wakeWord: String = "push" {
        didSet {
            UserDefaults.standard.set(wakeWord, forKey: UserDefaultsKeys.wakeWord)
        }
    }

    // MARK: - Hotkey Configuration

    enum Hotkey: String, CaseIterable, Identifiable {
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case rightCommand = "rightCommand"
        case leftCommand = "leftCommand"
        case rightControl = "rightControl"
        case leftControl = "leftControl"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .rightOption: return "⌥ Right Option"
            case .leftOption: return "⌥ Left Option"
            case .rightCommand: return "⌘ Right Command"
            case .leftCommand: return "⌘ Left Command"
            case .rightControl: return "⌃ Right Control"
            case .leftControl: return "⌃ Left Control"
            }
        }

        var flagMask: UInt64 {
            switch self {
            case .rightOption: return 0x40
            case .leftOption: return 0x20
            case .rightCommand: return 0x10
            case .leftCommand: return 0x08
            case .rightControl: return 0x2000
            case .leftControl: return 0x1
            }
        }

        var requiresAlternate: Bool {
            self == .rightOption || self == .leftOption
        }

        var requiresCommand: Bool {
            self == .rightCommand || self == .leftCommand
        }

        var requiresControl: Bool {
            self == .rightControl || self == .leftControl
        }
    }

    // MARK: - Model Enums

    enum WhisperModel: String, CaseIterable, Identifiable {
        case base = "ggml-base.en"
        case small = "ggml-small.en"
        case distilLargeV3 = "distil-large-v3"
        case distilLargeV3Turbo = "distil-large-v3-turbo"
        case whisperLargeV3Turbo = "whisper-large-v3-turbo"
        case moonshineTiny = "moonshine-tiny"
        case moonshineBase = "moonshine-base"
        case parakeetV2 = "parakeet-tdt-v2"
        // case qwen3ASR = "qwen3-asr" // TODO: Re-enable once MLX metallib bundling is resolved

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .base: return "Whisper Base"
            case .small: return "Whisper Small"
            case .distilLargeV3: return "Distil-Large V3"
            case .distilLargeV3Turbo: return "Distil-Large V3 Turbo"
            case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo"
            case .moonshineTiny: return "Moonshine Tiny"
            case .moonshineBase: return "Moonshine Base"
            case .parakeetV2: return "Parakeet TDT v2 — Fastest"
            }
        }

        var modelDescription: String {
            switch self {
            case .base: return "Fastest WhisperKit model, lower accuracy (~150 MB)"
            case .small: return "Good balance of speed and accuracy (~250 MB)"
            case .distilLargeV3: return "Fast and accurate, English-only (~600 MB)"
            case .distilLargeV3Turbo: return "Great speed and accuracy, English-only (~600 MB)"
            case .whisperLargeV3Turbo: return "High accuracy, 99+ languages (~632 MB)"
            case .moonshineTiny: return "Ultra-fast, optimized for short speech (~45 MB)"
            case .moonshineBase: return "Fast and accurate, variable-length audio (~134 MB)"
            case .parakeetV2: return "Best English accuracy, native punctuation (~400 MB). 16 GB+ recommended."
            }
        }

        /// The engine type used by this model
        var engineType: EngineType {
            switch self {
            case .base, .small, .distilLargeV3, .distilLargeV3Turbo, .whisperLargeV3Turbo:
                return .whisperKit
            case .moonshineTiny, .moonshineBase:
                return .moonshine
            case .parakeetV2:
                return .parakeet
            }
        }

        /// Whether this model uses the Moonshine engine instead of WhisperKit
        var isMoonshine: Bool { engineType == .moonshine }

        /// Whether this model produces high-quality native punctuation (skip punctuation post-processing)
        var hasNativePunctuation: Bool {
            switch self {
            case .parakeetV2: return true
            default: return false
            }
        }
    }

    /// Engine types for model routing
    enum EngineType {
        case whisperKit
        case moonshine
        case parakeet
    }

    // MARK: - Private

    private init() {
        // Load saved Whisper model from UserDefaults
        if let savedModel = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedWhisperModel),
           let model = WhisperModel(rawValue: savedModel) {
            self.selectedWhisperModel = model
        }
        self.activeModel = self.selectedWhisperModel

        // Load saved hotkey from UserDefaults
        if let savedHotkey = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedHotkey),
           let hotkey = Hotkey(rawValue: savedHotkey) {
            self.selectedHotkey = hotkey
        }

        // Load sound preference from UserDefaults
        self.playSoundOnStart = UserDefaults.standard.bool(forKey: UserDefaultsKeys.playSoundOnStart)

        // Load wake word settings from UserDefaults
        self.wakeWordEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.wakeWordEnabled)
        if let savedWakeWord = UserDefaults.standard.string(forKey: UserDefaultsKeys.wakeWord), !savedWakeWord.isEmpty {
            self.wakeWord = savedWakeWord
        }
    }

    private func notifyStateChange() {
        NotificationCenter.default.post(name: .appStateDidChange, object: nil)
    }
}
