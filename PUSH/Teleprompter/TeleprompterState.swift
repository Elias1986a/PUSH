import SwiftUI

/// The prompter's own settings. Deliberately not folded into `AppState`: this
/// is a second feature, and the two are read at different distances by
/// different people for different reasons.
@MainActor
final class TeleprompterState: ObservableObject {
    static let shared = TeleprompterState()

    private enum Keys {
        static let script = "prompterScript"
        static let size = "prompterSize"
        static let hideFromRecording = "prompterHideFromRecording"
        static let followVoice = "prompterFollowVoice"
        static let highlightSpoken = "prompterHighlightSpoken"
        static let wordsPerMinute = "prompterWordsPerMinute"
    }

    /// Type size. Line count is *not* a setting — the prompter always shows
    /// three lines, and a bigger size means bigger letters, not more of them.
    /// Height follows from the type.
    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 18
            case .medium: return 24
            case .large: return 32
            }
        }

        /// Column width. Narrow on purpose, and narrower than the dictation
        /// preview's box at the same name. That box widens to 800 because a
        /// wider box costs nothing at the bottom of the screen — true there,
        /// wrong here. A long line makes the eyes track left-to-right, and
        /// horizontal scanning is the same on-camera tell as vertical
        /// scanning. Broadcast prompters use narrow columns for this reason, and
        /// run four to eight words a line — these widths are set to land there
        /// at each type size, not to fill the notch.
        var width: CGFloat {
            switch self {
            case .small: return 320
            case .medium: return 380
            case .large: return 460
            }
        }

        /// Distance between the three lines' baselines.
        var lineHeight: CGFloat { fontSize * 1.35 }
    }

    @Published var script: String = TeleprompterState.sampleScript {
        didSet { UserDefaults.standard.set(script, forKey: Keys.script) }
    }

    @Published var size: Size = .medium {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: Keys.size) }
    }

    /// Excluded from screen capture. Default on — the whole point is that the
    /// prompter is for you, not for the viewer. Off is still worth offering:
    /// a tutorial screencast may well want it visible.
    @Published var hideFromScreenRecording: Bool = true {
        didSet { UserDefaults.standard.set(hideFromScreenRecording, forKey: Keys.hideFromRecording) }
    }

    @Published var followVoice: Bool = true {
        didSet { UserDefaults.standard.set(followVoice, forKey: Keys.followVoice) }
    }

    /// Dim the words already spoken on the line being read, so the exact place
    /// in the sentence is visible rather than just the line.
    ///
    /// A toggle rather than a fixed behaviour: word-level feedback is only
    /// worth having when alignment is right, and a wrong word marked as read is
    /// far more distracting than a whole line being slightly off.
    @Published var highlightSpokenWords: Bool = true {
        didSet { UserDefaults.standard.set(highlightSpokenWords, forKey: Keys.highlightSpoken) }
    }

    /// Pace for the timed fallback, used when voice-following is off or the
    /// model isn't available.
    @Published var wordsPerMinute: Double = 150 {
        didSet { UserDefaults.standard.set(wordsPerMinute, forKey: Keys.wordsPerMinute) }
    }

    private init() {
        let d = UserDefaults.standard
        if let saved = d.string(forKey: Keys.script), !saved.isEmpty { script = saved }
        if let raw = d.string(forKey: Keys.size), let v = Size(rawValue: raw) { size = v }
        if d.object(forKey: Keys.hideFromRecording) != nil {
            hideFromScreenRecording = d.bool(forKey: Keys.hideFromRecording)
        }
        if d.object(forKey: Keys.followVoice) != nil {
            followVoice = d.bool(forKey: Keys.followVoice)
        }
        if d.object(forKey: Keys.highlightSpoken) != nil {
            highlightSpokenWords = d.bool(forKey: Keys.highlightSpoken)
        }
        let wpm = d.double(forKey: Keys.wordsPerMinute)
        if wpm > 0 { wordsPerMinute = wpm }
    }

    static let sampleScript = """
    Hey everyone, welcome back to the channel. Today I want to show you \
    something I have been working on for a while, and I think you are going \
    to like it. The idea is simple: your notes should follow you, instead of \
    you chasing them. Let me show you what I mean.
    """
}
