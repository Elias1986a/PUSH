import Foundation
import CryptoKit

/// What travels between a person's Macs when they share what Type has learned:
/// the kept writing, and the moment they last pressed Delete All.
public struct TypingHistorySnapshot: Codable, Sendable, Equatable {
    /// Everything written before this is gone, on every Mac. Without it a Mac
    /// that was offline during Delete All would hand the old writing back.
    public var clearedAt: Date?
    public var records: [TypingHistoryRecord]

    public init(clearedAt: Date? = nil, records: [TypingHistoryRecord] = []) {
        self.clearedAt = clearedAt
        self.records = records
    }
}

/// Combining two Macs' copies of the history, and packing one for iCloud.
///
/// iCloud's key-value store holds 1 MB in all, shared with the settings and
/// the dictionary, so the history is compressed, sealed (AES-GCM, with a key
/// that lives in iCloud Keychain) and cut into chunks, newest writing first
/// if it must be trimmed to fit.
public enum TypingHistorySync {
    public static let maximumRecords = 5_000
    /// The most the sealed package may weigh, all chunks together.
    public static let budgetBytes = 600_000
    /// One KVS value. Several small keys rather than one large one.
    public static let chunkBytes = 96_000

    // MARK: - Merge

    /// The union of both copies, without what a Delete All removed, without
    /// copies of the same writing, newest 5,000 kept.
    public static func merge(_ a: TypingHistorySnapshot, _ b: TypingHistorySnapshot) -> TypingHistorySnapshot {
        let cleared = [a.clearedAt, b.clearedAt].compactMap { $0 }.max()
        var kept = (a.records + b.records).filter { record in cleared.map { record.date > $0 } ?? true }

        // The same writing on both Macs: keep one.
        var seen = Set<String>()
        kept = kept.filter { seen.insert($0.bundleID + "\u{1F}" + $0.text).inserted }

        // A shorter, earlier copy of a note that grew is replaced by the longer
        // one (the rule `TypingHistoryStore` applies on one Mac). Grouped by the
        // start of the text so the comparison stays cheap.
        var groups: [String: [Int]] = [:]
        for (i, r) in kept.enumerated() { groups[r.bundleID + "\u{1F}" + String(r.text.prefix(20)), default: []].append(i) }
        var drop = Set<Int>()
        for indexes in groups.values where indexes.count > 1 {
            let longestFirst = indexes.sorted { kept[$0].text.count > kept[$1].text.count }
            var survivors: [Int] = []
            for i in longestFirst {
                if survivors.contains(where: { kept[$0].text.contains(kept[i].text.prefix(200)) }) {
                    drop.insert(i)
                } else {
                    survivors.append(i)
                }
            }
        }
        kept = kept.enumerated().filter { !drop.contains($0.offset) }.map(\.element)

        kept.sort { $0.date < $1.date }
        if kept.count > maximumRecords { kept.removeFirst(kept.count - maximumRecords) }
        return TypingHistorySnapshot(clearedAt: cleared, records: kept)
    }

    // MARK: - Pack

    public enum Failure: Error { case truncated }

    /// The snapshot as sealed chunks that together fit `budgetBytes`; the
    /// oldest writing is left out until it does. Records are not changed on
    /// this Mac, only what is sent.
    public static func pack(_ snapshot: TypingHistorySnapshot, key: SymmetricKey,
                            budget: Int = budgetBytes) throws -> [Data] {
        var records = snapshot.records.sorted { $0.date < $1.date }
        while true {
            let json = try JSONEncoder().encode(TypingHistorySnapshot(clearedAt: snapshot.clearedAt, records: records))
            let compressed = try (json as NSData).compressed(using: .zlib) as Data
            guard let sealed = try AES.GCM.seal(compressed, using: key).combined else {
                throw CryptoKitError.incorrectParameterSize
            }
            if sealed.count <= budget || records.isEmpty {
                return stride(from: 0, to: sealed.count, by: chunkBytes).map {
                    sealed.subdata(in: $0..<min($0 + chunkBytes, sealed.count))
                }
            }
            // Over: drop the oldest tenth and try again.
            records.removeFirst(max(1, records.count / 10))
        }
    }

    public static func unpack(_ chunks: [Data], key: SymmetricKey) throws -> TypingHistorySnapshot {
        guard !chunks.isEmpty else { throw Failure.truncated }
        let sealed = chunks.reduce(into: Data()) { $0.append($1) }
        let compressed = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
        let json = try (compressed as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(TypingHistorySnapshot.self, from: json)
    }
}
