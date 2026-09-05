import SwiftUI
import AppKit
import Combine
import PUSHCore

/// The settings window.
///
/// A sidebar rather than a tab bar: the four tabs this replaced put eight
/// unrelated sections behind "General" — hotkey, sound, other apps' audio,
/// formatting, iCloud, pill, live preview, wake word — which is more than a tab
/// label can honestly describe and more than fits without scrolling.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var pane: Pane = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, dictation, text, pill, teleprompter, models, dictionary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .dictation: return "Dictation"
            case .text: return "Text"
            case .pill: return "Pill"
            case .teleprompter: return "Teleprompter"
            case .models: return "Models"
            case .dictionary: return "Dictionary"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .dictation: return "mic"
            case .text: return "text.alignleft"
            case .pill: return "capsule"
            case .teleprompter: return "text.viewfinder"
            case .models: return "cpu"
            case .dictionary: return "character.book.closed"
            }
        }
    }

    var body: some View {
        // A plain split rather than NavigationSplitView: inside a `Settings`
        // scene that container treats a frame as advisory and sizes itself from
        // content, which opened the window at 450×480, then 720×720, then
        // 900×696 across three attempts. A settings window has exactly one
        // right size, so it is stated here and nothing negotiates it.
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(width: 524)
        }
        .frame(width: 720, height: 640)
        .navigationTitle(pane.title)
    }

    private var sidebar: some View {
        List(Pane.allCases, selection: $pane) { item in
            Label(item.title, systemImage: item.symbol)
                .tag(item)
        }
        .listStyle(.sidebar)
        .frame(width: 196)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general:
            GeneralSettingsView().environmentObject(appState)
        case .dictation:
            DictationSettingsView().environmentObject(appState)
        case .text:
            TextSettingsView().environmentObject(appState)
        case .pill:
            PillSettingsView().environmentObject(appState)
        case .teleprompter:
            TeleprompterSettingsView()
        case .models:
            ModelsSettingsView().environmentObject(appState)
        case .dictionary:
            DictionarySettingsView()
        }
    }
}
