import Foundation
import UserNotifications

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
                print("NotificationManager: Failed to request permission: \(error)")
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
                print("NotificationManager: Failed to show notification: \(error)")
            }
        }
    }

    /// Show a microphone permission error
    func showMicrophoneError() {
        showError(
            title: "Microphone Access Required",
            message: "PUSH needs microphone access to record audio. Please grant access in System Settings."
        )
    }

    /// Show a transcription error
    func showTranscriptionError() {
        showError(
            title: "Transcription Failed",
            message: "Unable to transcribe audio. Please try again."
        )
    }

    /// Show a model loading error
    func showModelError() {
        showError(
            title: "Model Error",
            message: "Failed to load the Whisper model. Please check Settings."
        )
    }
}
