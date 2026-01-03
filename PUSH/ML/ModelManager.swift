import Foundation
import Combine

/// Manages model downloads, storage, and loading
@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()

    // MARK: - Published State

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadErrors: [String: String] = [:]

    // MARK: - Storage Paths

    private let appSupportDir: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("PUSH")
    }()

    var modelsDir: URL {
        appSupportDir.appendingPathComponent("models")
    }

    var whisperModelsDir: URL {
        modelsDir.appendingPathComponent("whisper")
    }

    var qwenModelsDir: URL {
        modelsDir.appendingPathComponent("qwen")
    }

    // MARK: - Model URLs

    private let whisperBaseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    private let qwenModelURLs: [String: String] = [
        "qwen3-0.6b-q4_k_m": "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
        "qwen3-1.7b-q4_k_m": "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        "qwen3-4b-q4_k_m": "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
    ]

    // MARK: - Private

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    private init() {
        createDirectories()
    }

    // MARK: - Public API

    /// Check if required models are downloaded
    func hasRequiredModels() -> Bool {
        let whisperModel = AppState.shared.selectedWhisperModel
        let qwenModel = AppState.shared.selectedQwenModel

        return isModelDownloaded(whisperModel.rawValue + ".bin") &&
               isModelDownloaded(qwenModel.rawValue + ".gguf")
    }

    /// Check if a specific model is downloaded
    func isModelDownloaded(_ modelName: String) -> Bool {
        let path = modelPath(for: modelName)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Get the path for a model file
    func modelPath(for modelName: String) -> URL {
        if modelName.contains("ggml") || modelName.contains("whisper") {
            return whisperModelsDir.appendingPathComponent(modelName.hasSuffix(".bin") ? modelName : modelName + ".bin")
        } else {
            return qwenModelsDir.appendingPathComponent(modelName.hasSuffix(".gguf") ? modelName : modelName + ".gguf")
        }
    }

    /// Download a Whisper model
    func downloadWhisperModel(_ model: AppState.WhisperModel) async {
        let filename = model.rawValue + ".bin"
        let url = URL(string: "\(whisperBaseURL)/\(filename)")!
        let destination = whisperModelsDir.appendingPathComponent(filename)

        await download(url: url, to: destination, modelName: model.rawValue)
    }

    /// Download a Qwen model
    func downloadQwenModel(_ model: AppState.QwenModel) async {
        guard let urlString = qwenModelURLs[model.rawValue],
              let url = URL(string: urlString) else {
            downloadErrors[model.rawValue] = "Invalid model URL"
            return
        }

        let filename = model.rawValue + ".gguf"
        let destination = qwenModelsDir.appendingPathComponent(filename)

        await download(url: url, to: destination, modelName: model.rawValue)
    }

    /// Cancel a download
    func cancelDownload(_ modelName: String) {
        downloadTasks[modelName]?.cancel()
        downloadTasks.removeValue(forKey: modelName)
        downloadProgress.removeValue(forKey: modelName)
    }

    /// Delete a model
    func deleteModel(_ modelName: String) throws {
        let path = modelPath(for: modelName)
        try FileManager.default.removeItem(at: path)
    }

    /// Get total size of downloaded models
    func totalModelSize() -> Int64 {
        var total: Int64 = 0

        let enumerator = FileManager.default.enumerator(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }

        return total
    }

    // MARK: - Private

    private func createDirectories() {
        try? FileManager.default.createDirectory(at: whisperModelsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: qwenModelsDir, withIntermediateDirectories: true)
    }

    private func download(url: URL, to destination: URL, modelName: String) async {
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destination.path) {
            print("ModelManager: \(modelName) already downloaded")
            return
        }

        print("ModelManager: Starting download of \(modelName) from \(url)")

        downloadProgress[modelName] = 0
        downloadErrors.removeValue(forKey: modelName)

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url) { [weak self] bytesWritten, totalBytesWritten, totalBytesExpectedToWrite in
                guard totalBytesExpectedToWrite > 0 else { return }
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

                Task { @MainActor [weak self] in
                    self?.downloadProgress[modelName] = progress
                }
            }

            // Move to destination
            try FileManager.default.moveItem(at: tempURL, to: destination)

            print("ModelManager: Downloaded \(modelName) to \(destination.path)")

            downloadProgress.removeValue(forKey: modelName)

        } catch {
            print("ModelManager: Download failed for \(modelName): \(error)")
            downloadErrors[modelName] = error.localizedDescription
            downloadProgress.removeValue(forKey: modelName)
        }
    }
}

// MARK: - URLSession download with progress

extension URLSession {
    func download(from url: URL, progressHandler: @escaping (Int64, Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(progressHandler: progressHandler) { result in
                continuation.resume(with: result)
            }

            let task = self.downloadTask(with: url)
            task.delegate = delegate

            // Store delegate to prevent deallocation
            objc_setAssociatedObject(task, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            task.resume()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressHandler: (Int64, Int64, Int64) -> Void
    let completionHandler: (Result<(URL, URLResponse), Error>) -> Void

    init(progressHandler: @escaping (Int64, Int64, Int64) -> Void,
         completionHandler: @escaping (Result<(URL, URLResponse), Error>) -> Void) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response else {
            completionHandler(.failure(URLError(.badServerResponse)))
            return
        }

        // Copy to a new temp location since the original will be deleted
        let tempDir = FileManager.default.temporaryDirectory
        let newLocation = tempDir.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.copyItem(at: location, to: newLocation)
            completionHandler(.success((newLocation, response)))
        } catch {
            completionHandler(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progressHandler(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }
}
