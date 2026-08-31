import SwiftUI
import Combine
import PUSHCore

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
        static let showLivePreview = "showLivePreview"
        static let previewSize = "previewSize"
        static let pillPosition = "pillPosition"
        static let resolveSelfCorrections = "resolveSelfCorrections"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
    }

    // MARK: - Published State

    @Published var isListening: Bool = false {
        didSet {
            // Reset the preview at the start of each dictation rather than at the
            // end of the last one: clearing it on completion would shrink the pill
            // mid fade-out. Doing it here also covers engines that emit no
            // partials, so stale text can never carry into the next dictation.
            if isListening { livePartialText = "" }
            notifyStateChange()
        }
    }

    @Published var isProcessing: Bool = false {
        didSet { notifyStateChange() }
    }

    /// True once the microphone is genuinely capturing, which is not the same as
    /// `isListening` — that flips the instant the key goes down, while the audio
    /// device can take seconds to come up on a cold press. The pill said
    /// "Listening" through a measured 4.2s wait and the user spoke into nothing.
    @Published var isCapturing: Bool = false {
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

    /// True from launch until *every* warm-up step is done: the ASR model, the
    /// chirp player, the capture engine and the VAD.
    ///
    /// `isModelReady` alone was a dishonest signal — the ASR model is ready in
    /// about a tenth of a second, while the capture path takes several more, so
    /// the pill went quiet and the app looked ready while a press was still slow
    /// (and, before the prewarm moved off the main thread, could be dropped
    /// outright). Same trap as the menu-bar hourglass: an indicator wired to the
    /// wrong subsystem is worse than none.
    @Published var isPrewarming: Bool = true {
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
    @Published var activeModel: WhisperModel = .parakeetUnified

    @Published var statusMessage: String = "Ready"

    /// Whether the pill should be on screen. The single source of truth for both
    /// the SwiftUI view's own visibility and AppDelegate's ordering of the panel
    /// — they were separate copies of this condition, and adding `isPrewarming`
    /// to only one of them meant the window was ordered out before the view could
    /// ever draw "Warming up…".
    var pillShouldShow: Bool {
        isListening || isProcessing || !isModelReady || isWarmingUp || isPrewarming
    }

    /// Parakeet Unified is the default for fresh installs, chosen after running
    /// every engine over the same recording in `compare/`: 8.3s of audio in
    /// 0.061s, the fastest of the four and the most accurate on English.
    ///
    /// It replaced Parakeet Streaming, whose case for the slot was that it
    /// consumes audio while you speak, so latency after release stays flat
    /// (~0.04s) where Unified's scales with length (~0.010s per second). That
    /// still holds, and Streaming remains the right pick for long-form
    /// dictation and the only one that shows text while you talk — but at
    /// ordinary utterance length the difference is imperceptible, and in the
    /// app's own logs Streaming returned nothing at all on 4 of 86 runs.
    @Published var selectedWhisperModel: WhisperModel = .parakeetUnified {
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

    /// Show the rough transcript in the pill while you speak. Only the streaming
    /// Parakeet engine emits partials; on every other engine this has no effect.
    /// Off by default: the text trails speech by ~2s, so it stays blank on short
    /// dictations and is worth opting into rather than meeting unannounced.
    @Published var showLivePreview: Bool = false {
        didSet {
            UserDefaults.standard.set(showLivePreview, forKey: UserDefaultsKeys.showLivePreview)
            if !showLivePreview { livePartialText = "" }
        }
    }

    /// How large the live preview draws. Scales the text and the width of the
    /// box it reserves.
    @Published var previewSize: PreviewSize = .medium {
        didSet {
            UserDefaults.standard.set(previewSize.rawValue, forKey: UserDefaultsKeys.previewSize)
        }
    }

    enum PreviewSize: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }

        /// Point size of the preview text. Drawn in the condensed system width
        /// (see `FloatingPillView`), so stepping up a size reads mostly as
        /// taller letters rather than a longer line.
        var fontSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            }
        }

        /// Width the preview reserves. Deliberately generous — the box is only
        /// as wide as it needs to be to delay the point where text starts
        /// scrolling, and a wider box costs nothing when it sits at the bottom
        /// of the screen.
        var width: CGFloat {
            switch self {
            case .small: return 400
            case .medium: return 600
            case .large: return 800
            }
        }
    }

    /// Whether settings and the dictionary follow the user across their Macs
    /// through iCloud. On by default: it needs no account and no setup, and
    /// the merge is additive — entries are unioned, never replaced wholesale.
    @Published var iCloudSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: UserDefaultsKeys.iCloudSyncEnabled)
            if iCloudSyncEnabled { CloudSync.shared.start() }
        }
    }

    /// Re-read the mirrored settings after a sync has written them underneath
    /// us. Assignment is skipped where the value is unchanged, so this doesn't
    /// churn the UI on every remote key.
    func reloadFromDefaults() {
        let d = UserDefaults.standard

        if let raw = d.string(forKey: UserDefaultsKeys.selectedWhisperModel),
           let v = WhisperModel(rawValue: raw), v != selectedWhisperModel {
            selectedWhisperModel = v
        }
        if let raw = d.string(forKey: UserDefaultsKeys.selectedHotkey),
           let v = Hotkey(rawValue: raw), v != selectedHotkey {
            selectedHotkey = v
        }
        if let raw = d.string(forKey: UserDefaultsKeys.mediaBehavior),
           let v = MediaBehavior(rawValue: raw), v != mediaBehavior {
            mediaBehavior = v
        }
        if let raw = d.string(forKey: UserDefaultsKeys.previewSize),
           let v = PreviewSize(rawValue: raw), v != previewSize {
            previewSize = v
        }
        let wake = d.string(forKey: UserDefaultsKeys.wakeWord) ?? wakeWord
        if wake != wakeWord, !wake.isEmpty { wakeWord = wake }

        let flags: [(Bool, ReferenceWritableKeyPath<AppState, Bool>)] = [
            (d.bool(forKey: UserDefaultsKeys.playSoundOnStart), \.playSoundOnStart),
            (d.bool(forKey: UserDefaultsKeys.wakeWordEnabled), \.wakeWordEnabled),
            (d.bool(forKey: UserDefaultsKeys.doubleSpaceAfterSentence), \.doubleSpaceAfterSentence),
            (d.bool(forKey: UserDefaultsKeys.showLivePreview), \.showLivePreview),
            (d.bool(forKey: UserDefaultsKeys.resolveSelfCorrections), \.resolveSelfCorrections)
        ]
        for (value, path) in flags where self[keyPath: path] != value {
            self[keyPath: path] = value
        }
    }

    /// Whether to act on spoken self-corrections — "the red car, I mean the
    /// blue car" pastes as "the blue car".
    ///
    /// Off by default, and it should stay off until it has been lived with:
    /// this is the only post-processing step that deletes words the user
    /// actually said, so its failure mode is losing meaning silently rather
    /// than formatting something oddly.
    @Published var resolveSelfCorrections: Bool = false {
        didSet {
            UserDefaults.standard.set(resolveSelfCorrections, forKey: UserDefaultsKeys.resolveSelfCorrections)
        }
    }

    /// Where the pill lives on screen. At the top it stops being a floating
    /// capsule and becomes a tab hanging off the screen's top edge, continuing
    /// the notch downward — the reading position for a live transcript, rather
    /// than the corner of the eye the bottom placement asks for.
    @Published var pillPosition: PillPosition = .bottom {
        didSet {
            UserDefaults.standard.set(pillPosition.rawValue, forKey: UserDefaultsKeys.pillPosition)
            notifyStateChange()
        }
    }

    enum PillPosition: String, CaseIterable, Identifiable {
        case bottom, top

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .bottom: return "Bottom"
            case .top: return "Top (notch)"
            }
        }
    }

    /// Clearance the top placement has to leave before it can draw: the notch
    /// on a MacBook, the menu bar everywhere else. Written by `AppDelegate`
    /// when it positions the window, because only it knows which screen the
    /// pill landed on. Not persisted, and deliberately not a state-change
    /// notification — it is measured *during* positioning.
    @Published var pillTopInset: CGFloat = 0

    /// Width the top placement claims at minimum, so the shape is always wider
    /// than the housing it descends from. A bare "Listening" pill measures
    /// about 100pt — narrower than the ~200pt notch it would then hide behind
    /// completely.
    static let notchMinimumWidth: CGFloat = 280

    /// Rough, un-cleaned transcript emitted mid-utterance by the streaming
    /// engine — display only, never injected and never logged. Append-only, so
    /// it grows rather than rewriting itself.
    ///
    /// Deliberately does NOT call `notifyStateChange()`: that notification drives
    /// pill window visibility, and this updates about once a second.
    @Published var livePartialText: String = ""

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

    /// Lifted into PUSHCore so the engines and the comparison tool can share them.
    /// Aliased here because `AppState.WhisperModel` reads naturally at every call site.
    typealias WhisperModel = PUSHCore.WhisperModel
    typealias EngineType = PUSHCore.EngineType

    // MARK: - Dictation Language

    /// The store the per-engine language preferences read and write.
    ///
    /// The only injectable defaults store in this class, and deliberately so.
    /// `UserDefaults.standard` here is the user's live app configuration: a test
    /// that wrote a language through `AppState.shared` would leave the real PUSH
    /// dictating in whatever language the test happened to pick, with nothing on
    /// screen connecting the two. Tests point this at a throwaway suite instead.
    ///
    /// Threading a store through every stored property above would be a much
    /// larger change than the reason for it justifies — those are all written
    /// from `didSet` on properties the user drives, not from tests.
    var languageDefaults: UserDefaults = .standard

    /// The language `model` should dictate in, English when never chosen.
    ///
    /// Stored per engine because each supports a different set — Nemotron reads
    /// its own `prompt_dictionary`, Apple queries `SpeechTranscriber
    /// .supportedLocales`. One shared key would seat an unsupported language the
    /// moment the user switched engines.
    ///
    /// The stored string is *constructed into* a `DictationLanguage` rather than
    /// compared as a raw string, and that is load-bearing: `init` canonicalizes,
    /// so a preference persisted in Apple's underscore form ("en_US") only
    /// matches an offered hyphenated code ("en-US") after construction. Compare
    /// the raw value and a saved choice silently fails to select in the picker.
    func language(for model: WhisperModel) -> DictationLanguage {
        DictationLanguage(code: languageDefaults.string(forKey: model.languageDefaultsKey) ?? "en-US")
    }

    /// Records the user's language choice for one engine.
    ///
    /// Hand-published rather than backed by a `@Published` property: the value
    /// is keyed by engine, so there is nothing for one stored property to hold,
    /// and the picker still needs the view to redraw.
    func setLanguage(_ language: DictationLanguage, for model: WhisperModel) {
        languageDefaults.set(language.code, forKey: model.languageDefaultsKey)
        objectWillChange.send()
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

        // Load live preview preference (bool(forKey:) is false when never set,
        // which is the intended default)
        self.showLivePreview = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showLivePreview)
        if let savedSize = UserDefaults.standard.string(forKey: UserDefaultsKeys.previewSize),
           let size = PreviewSize(rawValue: savedSize) {
            self.previewSize = size
        }
        if let savedPosition = UserDefaults.standard.string(forKey: UserDefaultsKeys.pillPosition),
           let position = PillPosition(rawValue: savedPosition) {
            self.pillPosition = position
        }
        self.resolveSelfCorrections = UserDefaults.standard.bool(forKey: UserDefaultsKeys.resolveSelfCorrections)
        // Defaults to true when never set, unlike every other flag here.
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.iCloudSyncEnabled) != nil {
            self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.iCloudSyncEnabled)
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
