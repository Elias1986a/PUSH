import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status - only show when actively listening or processing
            if appState.isListening || appState.isProcessing {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.statusMessage)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Hotkey info - dynamically show selected hotkey
            HStack {
                Text("Hold")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(appState.selectedHotkey.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                Text("to speak")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Settings button
            SettingsLink {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Quit button
            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit PUSH")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 200)
    }

    private var statusColor: Color {
        if appState.isProcessing {
            return .orange
        } else if appState.isListening {
            return .green
        } else {
            return .blue
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
