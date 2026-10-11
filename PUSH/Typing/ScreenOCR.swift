import AppKit
import ScreenCaptureKit
import Vision
import PUSHCore

/// The fallback for apps whose text Accessibility cannot see (some games,
/// remote desktops, a few custom-drawn editors): capture the window and read
/// it with Apple's on-device text recognition (Vision; not Apple
/// Intelligence). Needs Screen Recording, which is only asked for from
/// Settings → Typing. The capture is never kept or logged.
enum ScreenOCR {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Lines of text in `pid`'s frontmost window, in AppKit screen points.
    static func read(pid: pid_t) async -> [ScreenTextSelector.Item] {
        guard isAllowed,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: {
                  $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 100
              }) else { return [] }
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.screens.first { $0.frame.intersects(window.frame) }?.backingScaleFactor ?? 2
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        // SCWindow frames are top-left origin; flip to AppKit for the selector.
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let frame = CGRect(x: window.frame.minX, y: screenHeight - window.frame.maxY,
                           width: window.frame.width, height: window.frame.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox   // normalized, bottom-left origin
            return .init(text: text, frame: CGRect(x: frame.minX + box.minX * frame.width,
                                                   y: frame.minY + box.minY * frame.height,
                                                   width: box.width * frame.width, height: box.height * frame.height))
        }
    }
}
