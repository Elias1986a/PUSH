import Foundation

/// Comparison history, appended as JSONL beside the app's own support directory.
///
/// Append on write, atomic rewrite on delete: a partial write here would lose history
/// the user didn't ask to delete. Decoding is per-line and lenient, so one unreadable
/// row from an older schema costs that row rather than the file.
@MainActor
enum RunLog {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PUSHCompare", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var fileURL: URL { directory.appendingPathComponent("comparisons.jsonl") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func append(_ comparison: Comparison) {
        guard var line = try? encoder.encode(comparison) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    static func load() -> [Comparison] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap {
            try? decoder.decode(Comparison.self, from: Data($0))
        }
    }

    static func delete(id: UUID) {
        rewrite(load().filter { $0.id != id })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func rewrite(_ comparisons: [Comparison]) {
        let body = comparisons.compactMap { c -> String? in
            guard let data = try? encoder.encode(c) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
        try? (body.isEmpty ? "" : body + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
