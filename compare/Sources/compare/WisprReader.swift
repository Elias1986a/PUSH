import Foundation
import SQLite3

/// One Wispr Flow result for an utterance.
struct WisprRun: Codable, Sendable {
    /// Their raw ASR, before their own cleanup pass.
    let raw: String
    /// After their cleanup — the equivalent of our postProcess.
    let formatted: String
    /// Round trip as they measure it, in seconds. Includes the network.
    let e2eSeconds: Double
    /// The network portion, in seconds. Subtracting it gives something closer to a
    /// like-for-like comparison against a local engine's compute time.
    let networkSeconds: Double

    /// End-to-end minus the network. Still not identical to local compute — their
    /// server queueing is in here — but far closer than e2e alone.
    var processingSeconds: Double { max(e2eSeconds - networkSeconds, 0) }
}

/// Reads Wispr Flow's own result for an utterance out of its local database.
///
/// Wispr is closed and has no API, but it records every dictation to
/// `~/Library/Application Support/Wispr Flow/flow.sqlite` — raw ASR, their cleaned-up
/// text, and their latency. That is the same split this tool already shows for local
/// engines, which is what makes a real side-by-side possible.
///
/// Strictly read-only. Wispr owns this file; we never write to it.
enum WisprReader {

    /// Their cleanup is server-side, so the row lands after every local engine has
    /// finished. Hence polling rather than a single read.
    private static let pollInterval: Duration = .milliseconds(300)

    /// How far either side of the hold to look. Wispr stamps a row with the *start* of
    /// its own utterance, and the two hotkeys are never pressed on the same millisecond.
    private static let grace: TimeInterval = 6

    static var databaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wispr Flow/flow.sqlite")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    /// Why there is no Wispr result, so the card can say so.
    ///
    /// An absent row used to render as nothing at all, which is indistinguishable from
    /// the tool being broken — and that is exactly how it read.
    enum Absence: String, Error {
        case notInstalled = "Wispr Flow isn't installed"
        case notRunning = "Wispr Flow isn't running — its database can only be read while it is open"
        case noResult = "Wispr Flow didn't transcribe this one — hold its hotkey while you talk"
    }

    /// Wait for the first Wispr row recorded around `holdStarted`.
    static func result(around holdStarted: Date, timeout: TimeInterval) async -> Result<WisprRun, Absence> {
        guard isInstalled else { return .failure(.notInstalled) }

        let lower = stamp(holdStarted.addingTimeInterval(-grace))
        let upper = stamp(holdStarted.addingTimeInterval(grace))
        let deadline = Date().addingTimeInterval(timeout)
        var everOpened = false

        while Date() < deadline {
            switch fetch(between: lower, and: upper) {
            case .row(let run):
                return .success(run)
            case .openedButNoRow:
                everOpened = true
            case .couldNotOpen:
                break
            }
            try? await Task.sleep(for: pollInterval)
        }

        // Distinguishing these two is the whole point: one means "hold the other hotkey
        // too", the other means "launch the app first".
        return .failure(everOpened ? .noResult : .notRunning)
    }

    private enum FetchOutcome {
        case row(WisprRun)
        case openedButNoRow
        case couldNotOpen
    }

    /// Their timestamps look like "2026-08-21 00:34:24.757 +00:00" — UTC with an
    /// explicit offset suffix, which the query trims before comparing.
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func fetch(between lower: String, and upper: String) -> FetchOutcome {
        var db: OpaquePointer?

        // Read-only, and via the URI form so the connection can never be upgraded to a
        // writer.
        //
        // `immutable` is deliberately NOT set. The database runs in WAL mode: recent
        // dictations live in flow.sqlite-wal and only fold into the main file at a
        // checkpoint. Opening immutable ignores the WAL and returns whatever was last
        // checkpointed — which here was *February*. That is not a hypothetical; it is
        // how this was first misdiagnosed as a stale database.
        //
        // The corollary: the -shm sidecar only exists while Wispr is running, and
        // read-only mode cannot create it. If Wispr is closed this open fails, which is
        // correct — a closed Wispr has no result for this utterance anyway.
        let uri = "file:\(databaseURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            // Almost always SQLITE_CANTOPEN because Wispr is closed: a WAL database
            // cannot be opened read-only unless its -shm sidecar already exists, and a
            // read-only connection is not allowed to create one.
            sqlite3_close(db)
            return .couldNotOpen
        }
        defer { sqlite3_close(db) }

        // Wispr creates the row when the utterance starts and fills the text in
        // afterwards, so rows with no text yet are skipped rather than returned empty —
        // otherwise the first poll happily reports the *previous* dictation's result.
        let sql = """
            SELECT COALESCE(NULLIF(asrText, ''), formattedText),
                   COALESCE(NULLIF(formattedText, ''), asrText),
                   COALESCE(e2eLatency, 0), COALESCE(clientNetworkLatency, 0)
            FROM History
            WHERE substr(timestamp, 1, 23) > ?
              AND substr(timestamp, 1, 23) < ?
              AND COALESCE(NULLIF(formattedText, ''), asrText) IS NOT NULL
            ORDER BY timestamp DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return .couldNotOpen }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (lower as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (upper as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawText = sqlite3_column_text(statement, 0),
              let formattedText = sqlite3_column_text(statement, 1)
        else { return .openedButNoRow }

        let raw = String(cString: rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .openedButNoRow }

        // Both latencies are milliseconds in their schema.
        return .row(WisprRun(
            raw: raw,
            formatted: String(cString: formattedText).trimmingCharacters(in: .whitespacesAndNewlines),
            e2eSeconds: sqlite3_column_double(statement, 2) / 1000,
            networkSeconds: sqlite3_column_double(statement, 3) / 1000))
    }
}
