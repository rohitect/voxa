import Foundation
import WhisperKit

/// Manages WhisperKit model downloads, caching, and selection.
@Observable
final class ModelManager {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready(path: String)
        case error(String)
    }

    /// Available model variants (ordered small → large)
    static let availableModels = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-large-v3_turbo_954MB",
        "openai_whisper-large-v3_turbo",
        "openai_whisper-large-v3",
    ]

    var selectedModel: String = "openai_whisper-large-v3_turbo"
    var modelState: ModelState = .notDownloaded
    var availableLocalModels: [String] = []

    private let modelsDirectory: URL

    init() {
        modelsDirectory = Constants.dataDirectory.appendingPathComponent("Models", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Check if selected model is already downloaded
        refreshLocalModels()
    }

    /// Scans the models directory recursively for already-downloaded models.
    func refreshLocalModels() {
        availableLocalModels = findAllModelDirs().map { $0.lastPathComponent }

        if let localPath = localModelPath(for: selectedModel) {
            modelState = .ready(path: localPath)
        } else {
            modelState = .notDownloaded
        }
    }

    /// Returns the local path for a model if it exists, nil otherwise.
    func localModelPath(for model: String) -> String? {
        for dir in findAllModelDirs() {
            if dir.lastPathComponent == model {
                return dir.path
            }
        }
        return nil
    }

    /// Recursively finds directories that match known model variant names.
    private func findAllModelDirs() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let knownModels = Set(Self.availableModels)
        var results: [URL] = []

        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, knownModels.contains(url.lastPathComponent) {
                results.append(url)
            }
        }
        return results
    }

    /// Downloads the selected model using WhisperKit's built-in downloader.
    func downloadSelectedModel() async {
        await downloadModel(selectedModel)
    }

    /// Downloads a specific model variant.
    func downloadModel(_ variant: String) async {
        guard modelState != .downloading(progress: 0) else { return }

        modelState = .downloading(progress: 0)

        do {
            let modelFolder = try await WhisperKit.download(
                variant: variant,
                downloadBase: modelsDirectory,
                useBackgroundSession: false,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.modelState = .downloading(progress: progress.fractionCompleted)
                    }
                }
            )

            modelState = .ready(path: modelFolder.path)
            refreshLocalModels()
            print("[ModelManager] Model downloaded: \(variant) → \(modelFolder)")
        } catch {
            modelState = .error(error.localizedDescription)
            print("[ModelManager] Download failed: \(error)")
        }
    }

    /// Selects a different model. If already downloaded, switches immediately.
    func selectModel(_ variant: String) {
        selectedModel = variant
        if let localPath = localModelPath(for: variant) {
            modelState = .ready(path: localPath)
        } else {
            modelState = .notDownloaded
        }
    }

    /// Returns the recommended model for this device.
    func recommendedModel() -> String {
        let recommended = WhisperKit.recommendedModels()
        return recommended.default
    }
}
