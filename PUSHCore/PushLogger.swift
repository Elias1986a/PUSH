import Foundation
import OSLog

public enum PushLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PUSH",
        category: "push"
    )
    private static let queue = DispatchQueue(label: "push.logger")

    public static func log(_ message: String) {
        // Emit to the unified log in ALL builds so `log show` can surface
        // diagnostics from release builds. These are operational events only
        // (no transcription text), so .public keeps them readable.
        logger.notice("\(message, privacy: .public)")

        // Also mirror to a file in ALL builds. `log show` has proven unreliable
        // for surfacing these from a release build, which left cold-start
        // problems undiagnosable — the file is the only record that survives.
        // Safe to ship: PushLogger events are operational only and never
        // include transcript text.
        queue.async {
            guard let url = logFileURL else { return }
            Self.trimIfNeeded(url)
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
    }

    /// Keep the log bounded now that it runs in release builds: past the cap,
    /// drop the oldest half rather than letting it grow without limit.
    private static let maxLogBytes = 512 * 1024

    private static func trimIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxLogBytes,
              let data = try? Data(contentsOf: url) else { return }

        let keep = data.suffix(maxLogBytes / 2)
        // Start at a line boundary so the file never opens mid-entry.
        let trimmed = keep.firstIndex(of: UInt8(ascii: "\n")).map { keep[(keep.index(after: $0))...] } ?? keep
        try? Data(trimmed).write(to: url)
    }

    private static var logFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("PUSH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("push_debug.log")
    }
}
