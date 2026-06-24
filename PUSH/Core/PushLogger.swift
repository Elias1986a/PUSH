import Foundation
import OSLog

enum PushLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PUSH",
        category: "push"
    )
    private static let queue = DispatchQueue(label: "push.logger")

    static func log(_ message: String) {
        // Emit to the unified log in ALL builds so `log show` can surface
        // diagnostics from release builds. These are operational events only
        // (no transcription text), so .public keeps them readable.
        logger.notice("\(message, privacy: .public)")

        #if DEBUG
        queue.async {
            guard let url = logFileURL else { return }
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            let line = "\(timestamp): \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: url.path),
               let fileHandle = FileHandle(forWritingAtPath: url.path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }

    #if DEBUG
    private static var logFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("PUSH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("push_debug.log")
    }
    #endif
}
