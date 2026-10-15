import Foundation
import UserNotifications
import PUSHCore

/// Manages user notifications for errors and alerts
@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private init() {
        requestPermission()
    }

    /// Request notification permission
    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                PushLogger.log("NotificationManager: Failed to request permission: \(error)")
            }
        }
    }

    /// Show an error notification
    func showError(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                PushLogger.log("NotificationManager: Failed to show notification: \(error)")
            }
        }
    }

    /// Show a microphone permission error
    func showMicrophoneError() {
        showError(
            title: "Microphone is off for PUSHTYPE",
            message: "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone."
        )
    }

    /// Show a transcription error
    func showTranscriptionError() {
        showError(
            title: "Nothing was transcribed",
            message: "Hold the key and try again. If it keeps happening, pick another model in Settings ▸ Models."
        )
    }

    /// Show a model loading error
    func showModelError() {
        showError(
            title: "Speech model didn't load",
            message: "Open Settings ▸ Models to pick or re-download one."
        )
    }
}
