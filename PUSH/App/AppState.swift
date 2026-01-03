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

        // Load saved hotkey from UserDefaults
        if let savedHotkey = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedHotkey),
           let hotkey = Hotkey(rawValue: savedHotkey) {
            self.selectedHotkey = hotkey
        }

        // Load sound preference from UserDefaults
        self.playSoundOnStart = UserDefaults.standard.bool(forKey: UserDefaultsKeys.playSoundOnStart)
    }

    private func notifyStateChange() {
        NotificationCenter.default.post(name: .appStateDidChange, object: nil)
    }
}
