import SwiftUI
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var pillWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set Metal shader resource path for llama.cpp
        // This must happen before any model loading to ensure Metal can find ggml-metal.metal + ggml-common.h
        setupMetalResources()

        // Request permissions
        requestMicrophonePermission()

        // Initialize hotkey manager (will handle accessibility permission itself)
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.startListening()

        // Setup floating pill window
        setupFloatingPillWindow()

        // Start Sparkle auto-updater so scheduled checks run even before the
        // menu bar item is first opened.
        _ = UpdaterManager.shared

        // Pre-load Whisper model in background (will download if needed)
        preloadModels()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stopListening()
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showPermissionAlert(for: "Microphone")
                }
            }
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Access Required"
        alert.informativeText = "PUSH needs \(permission.lowercased()) access to function. Please grant access in System Settings > Privacy & Security."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Metal Resources

    private func setupMetalResources() {
        // llama.cpp's Metal backend needs to find ggml-metal.metal and ggml-common.h
        // at runtime to compile shaders. Set GGML_METAL_PATH_RESOURCES to the bundle
        // containing these files so ggml_metal_init can find them.
        if let bundlePath = Bundle.main.path(forResource: "llama_llama", ofType: "bundle") {
            setenv("GGML_METAL_PATH_RESOURCES", bundlePath, 1)
            PushLogger.log("AppDelegate: Set GGML_METAL_PATH_RESOURCES = \(bundlePath)")
        } else {
            // Fallback: try to find the bundle relative to app bundle
            let resourcePath = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/llama_llama.bundle").path
            if FileManager.default.fileExists(atPath: resourcePath) {
                setenv("GGML_METAL_PATH_RESOURCES", resourcePath, 1)
                PushLogger.log("AppDelegate: Set GGML_METAL_PATH_RESOURCES (fallback) = \(resourcePath)")
            } else {
                PushLogger.log("AppDelegate: WARNING - Could not find llama_llama.bundle for Metal resources")
                PushLogger.log("AppDelegate: mainBundle = \(Bundle.main.bundleURL.path)")
                PushLogger.log("AppDelegate: Tried: \(resourcePath)")
            }
        }
    }

    // MARK: - Floating Pill Window

    private func setupFloatingPillWindow() {
        let pillView = FloatingPillView()
            .environmentObject(AppState.shared)

        let hostingController = NSHostingController(rootView: pillView)

        // Use NSPanel with .nonactivatingPanel so showing it doesn't activate the app
        // or pull the user out of full-screen mode
        let window = NSPanel(contentViewController: hostingController)
        window.styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Force a layout to get the actual window size
            hostingController.view.layoutSubtreeIfNeeded()
            let windowSize = hostingController.view.fittingSize
            window.setContentSize(windowSize)

            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.minY + 10  // 10px from bottom
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.pillWindow = window

        // Observe app state to show/hide pill
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePillVisibility),
            name: .appStateDidChange,
            object: nil
        )
    }

    @objc private func updatePillVisibility() {
        DispatchQueue.main.async {
            let state = AppState.shared
            if state.isListening || state.isProcessing || !state.isModelReady || state.isWarmingUp {
                self.pillWindow?.orderFront(nil)
            } else {
                self.pillWindow?.orderOut(nil)
            }
        }
    }

    private func preloadModels() {
        Task { @MainActor in
            let selectedModel = AppState.shared.selectedWhisperModel
            PushLogger.log("AppDelegate: Loading model: \(selectedModel)...")
            AppState.shared.statusMessage = "Loading AI model..."

            let loadStart = Date()

            // Phase 1: Load the model (blocking) — makes the app usable
            switch selectedModel.engineType {
            case .moonshine:
                try? await MoonshineEngine.shared.loadModel(selectedModel)
            case .parakeet:
                try? await ParakeetEngine.shared.loadModel()
            case .whisperKit:
                try? await WhisperEngine.shared.loadModel(selectedModel)
            }

            let loadElapsed = Date().timeIntervalSince(loadStart)
            PushLogger.log("AppDelegate: Model loaded in \(String(format: "%.2f", loadElapsed))s")
            AppState.shared.isModelReady = true
            AppState.shared.statusMessage = "Ready"

            // Phase 2: Warm shaders in background (non-blocking).
            // The app is already usable; surface a "Warming up…" indicator so the
            // user knows why the very first transcription may be slightly slower.
            PushLogger.log("AppDelegate: Starting background shader warmup...")
            AppState.shared.isWarmingUp = true
            AppState.shared.statusMessage = "Warming up AI model…"
            switch selectedModel.engineType {
            case .moonshine:
                await MoonshineEngine.shared.warmupInference()
            case .parakeet:
                await ParakeetEngine.shared.warmup()
            case .whisperKit:
                await WhisperEngine.shared.warmupInference()
            }
            AppState.shared.isWarmingUp = false
            if AppState.shared.statusMessage == "Warming up AI model…" {
                AppState.shared.statusMessage = "Ready"
            }
            PushLogger.log("AppDelegate: Background shader warmup complete")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appStateDidChange = Notification.Name("appStateDidChange")
}
