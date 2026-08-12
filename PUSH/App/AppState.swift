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
        static let doubleSpaceAfterSentence = "doubleSpaceAfterSentence"
        static let mediaBehavior = "mediaBehavior"
        static let showLiveTranscript = "showLiveTranscript"
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
    @Published var activeModel: WhisperModel = .parakeetStreaming

    @Published var statusMessage: String = "Ready"

    /// The running transcript from the streaming engine, updated while the user
    /// is still speaking. Provisional in two ways: it lags speech by about the
    /// engine's chunk + lookahead window, and none of TranscriptionPipeline's
    /// post-processing has run on it yet — so it can differ from the text that
    /// finally gets injected. Always empty for the batch engines, which have no
    /// partial-result API.
    ///
    /// Deliberately does not call `notifyStateChange()`: this updates roughly
    /// once a second during dictation and drives nothing but the pill's label.
    @Published var liveTranscript: String = ""

    /// Whether the pill previews speech as it's transcribed. On by default;
    /// off restores the plain "Listening" indicator.
    @Published var showLiveTranscript: Bool = true {
        didSet {
            UserDefaults.standard.set(showLiveTranscript, forKey: UserDefaultsKeys.showLiveTranscript)
        }
    }

    /// Parakeet Streaming is the default for fresh installs, chosen after an
    /// A/B on real dictation. It consumes audio while you speak, so latency
    /// after release is near-constant (0.068s on 6s of audio, 0.086s on 26s)
    /// where the offline encoder scales with length (0.148s → 0.492s). Output
    /// matched Unified word for word on the same passage.
    @Published var selectedWhisperModel: WhisperModel = .parakeetStreaming {
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

    /// What to do about other apps' audio while dictating: nothing, pause it
    /// (media key), or duck the output volume. Defaults to ducking — it works
    /// on every setup and can't mis-target the wrong app, whereas pausing
    /// depends on the media app honoring the play/pause key.
    @Published var mediaBehavior: MediaBehavior = .duck {
        didSet {
            UserDefaults.standard.set(mediaBehavior.rawValue, forKey: UserDefaultsKeys.mediaBehavior)
        }
    }

    /// Typographic preference: two spaces after sentence-ending punctuation.
    /// Defaults to true to preserve the app's historical behavior.
    @Published var doubleSpaceAfterSentence: Bool = true {
        didSet {
            UserDefaults.standard.set(doubleSpaceAfterSentence, forKey: UserDefaultsKeys.doubleSpaceAfterSentence)
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
        case whisperLargeV3Turbo = "whisper-large-v3-turbo"
        case moonshineTiny = "moonshine-tiny"
        case parakeetV2 = "parakeet-tdt-v2"
        case parakeetUnified = "parakeet-unified"
        case parakeetStreaming = "parakeet-streaming"
        // case qwen3ASR = "qwen3-asr" // TODO: Re-enable once MLX metallib bundling is resolved.
        // Spike finding (claude/mlx-bundling-spike, now deleted): the GPU test
        // passed and the metallib loads fine — it lives at
        // Contents/Resources/default.metallib inside mlx-swift_Cmlx.bundle, not
        // at the bundle's top level. Prime suspect for the .app failure is that
        // build_distribution.sh copies the nested *.bundle into Resources but
        // never code-signs it. Start there if resuming.

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .base: return "Whisper Base"
            case .small: return "Whisper Small"
            case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo"
            case .moonshineTiny: return "Moonshine Tiny"
            case .parakeetV2: return "Parakeet TDT v2 — Smallest download"
            case .parakeetUnified: return "Parakeet Unified — Most accurate"
            case .parakeetStreaming: return "Parakeet Streaming — Fastest & balanced"
            }
        }

        var modelDescription: String {
            switch self {
            case .base: return "Fastest WhisperKit model, lower accuracy (~150 MB)"
            case .small: return "Good balance of speed and accuracy (~250 MB)"
            case .whisperLargeV3Turbo: return "High accuracy, 99+ languages (~632 MB)"
            case .moonshineTiny: return "Ultra-fast, optimized for short speech (~45 MB)"
            case .parakeetV2: return "Older English model, smaller download (~400 MB)."
            case .parakeetUnified: return "Highest accuracy. Transcribes after you release, so longer takes wait longer (~600 MB)."
            case .parakeetStreaming: return "Transcribes while you speak, so text lands instantly however long you talk. Same download as Unified (~600 MB)."
            }
        }

        /// The engine type used by this model
        var engineType: EngineType {
            switch self {
            case .base, .small, .whisperLargeV3Turbo:
                return .whisperKit
            case .moonshineTiny:
                return .moonshine
            case .parakeetV2:
                return .parakeet
            case .parakeetUnified:
                return .parakeetUnified
            case .parakeetStreaming:
                return .parakeetStreaming
            }
        }

        /// Whether this model uses the Moonshine engine instead of WhisperKit
        var isMoonshine: Bool { engineType == .moonshine }

        /// Whether this model produces high-quality native punctuation (skip punctuation post-processing)
        var hasNativePunctuation: Bool {
            switch self {
            case .parakeetV2, .parakeetUnified, .parakeetStreaming: return true
            default: return false
            }
        }
    }

    /// Engine types for model routing
    enum EngineType {
        case whisperKit
        case moonshine
        case parakeet
        case parakeetUnified
        case parakeetStreaming
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

        // Load formatting preference (default true when never set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.doubleSpaceAfterSentence) != nil {
            self.doubleSpaceAfterSentence = UserDefaults.standard.bool(forKey: UserDefaultsKeys.doubleSpaceAfterSentence)
        }

        // Load live-preview preference (default true when never set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.showLiveTranscript) != nil {
            self.showLiveTranscript = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showLiveTranscript)
        }

        // Load media behavior (keeps the .duck default when never set)
        if let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.mediaBehavior),
           let behavior = MediaBehavior(rawValue: saved) {
            self.mediaBehavior = behavior
        }

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
