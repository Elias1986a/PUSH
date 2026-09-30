import Foundation
import FluidAudio

/// Where Parakeet Streaming's model lives on disk.
///
/// Streaming is the chunked-attention export of FluidAudio's Parakeet Unified
/// repo. The same repo also holds the offline full-attention encoder, which
/// PUSH shipped as its own engine until 8.2.5 and then dropped: after decoding
/// while you talk, it was neither faster nor more accurate than Ultra, and it
/// is English only (measured on 13 readings of the benchmark passage).
public enum ParakeetUnifiedFiles {

    /// FluidAudio's model directory for the Parakeet Unified repo.
    ///
    /// Derived from `Repo.folderName` rather than hardcoded: the local folder
    /// is not the HuggingFace repo name (FluidAudio strips the "-coreml"
    /// suffix), and hardcoding it once already produced a false
    /// "Not downloaded" in Settings while the model was loaded and serving.
    public static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    /// The repo holds two ~600 MB encoders — offline (retired) and streaming —
    /// plus a few MB of decoder and joint both use. FluidAudio downloads each
    /// encoder only when that mode loads, so presence is per encoder.
    public static let offlineEncoderFile = ModelNames.ParakeetUnified.offlineEncoderFile(precision: .int8)
    public static let streamingEncoderFile = ModelNames.ParakeetUnified.streamingEncoderFile(
        precision: .int8, contextSuffix: UnifiedConfig().contextSuffix)
    static let sharedFiles = [
        ModelNames.ParakeetUnified.decoderFile, ModelNames.ParakeetUnified.jointDecisionFile,
    ]

    /// Whether `encoder` and the shared files it needs are on disk.
    public static func hasMode(encoder: String, in dir: URL = modelDirectory) -> Bool {
        ([encoder] + sharedFiles).allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    /// Remove one mode's encoder; remove the whole folder (shared files
    /// included) only once the other mode's encoder is gone too.
    static func deleteMode(
        encoder: String, keepingIfPresent other: String, in dir: URL = modelDirectory
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        if fm.fileExists(atPath: dir.appendingPathComponent(other).path) {
            let file = dir.appendingPathComponent(encoder)
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            PushLogger.log("ParakeetUnified: deleted \(encoder), kept the other mode")
        } else {
            try fm.removeItem(at: dir)
            PushLogger.log("ParakeetUnified: deleted \(dir.path)")
        }
    }

    /// Free the retired offline encoder's ~600 MB if an earlier version
    /// downloaded it. Streaming's files are left alone.
    public static func removeRetiredOfflineEncoder(in dir: URL = modelDirectory) {
        let file = dir.appendingPathComponent(offlineEncoderFile)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try deleteMode(encoder: offlineEncoderFile, keepingIfPresent: streamingEncoderFile, in: dir)
        } catch {
            PushLogger.log("ParakeetUnified: could not remove the retired offline encoder: \(error)")
        }
    }

    /// Bytes a mode occupies: its encoder plus the shared files.
    public static func modeSize(encoder: String) -> Double {
        ([encoder] + sharedFiles).reduce(0) { total, name in
            total + directoryBytes(modelDirectory.appendingPathComponent(name))
        }
    }

    private static func directoryBytes(_ url: URL) -> Double {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Double = 0
        for case let f as URL in e {
            total += Double((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
