import Foundation
import FluidAudio
import WhisperKit

/// Manages STT model downloads, caching, and selection for both WhisperKit and Parakeet.
@Observable
final class ModelManager {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready(path: String)
        case error(String)
    }

    /// Available WhisperKit model variants (ordered small → large)
    static let whisperKitModels = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-large-v3_turbo_954MB",
        "openai_whisper-large-v3_turbo",
        "openai_whisper-large-v3",
    ]

    /// Available Parakeet model variants
    static let parakeetModels = [
        "parakeet-tdt-0.6b-v2",
        "parakeet-tdt-0.6b-v3",
    ]

    /// Returns model list for the given provider.
    static func availableModels(for provider: STTProvider) -> [String] {
        switch provider {
        case .whisperKit: whisperKitModels
        case .parakeet: parakeetModels
        }
    }

    /// Default model per provider.
    static func defaultModel(for provider: STTProvider) -> String {
        switch provider {
        case .whisperKit: "openai_whisper-large-v3_turbo"
        case .parakeet: "parakeet-tdt-0.6b-v2"
        }
    }

    var selectedModel: String
    var modelState: ModelState = .notDownloaded
    var availableLocalModels: [String] = []

    /// Called when a model becomes ready (after download or selection). Set by AppState.
    var onModelReady: ((String) -> Void)?
    var provider: STTProvider {
        didSet {
            if oldValue != provider {
                selectedModel = UserDefaults.standard.string(forKey: "selectedModel.\(provider.rawValue)")
                    ?? Self.defaultModel(for: provider)
                refreshLocalModels()
            }
        }
    }

    private let modelsDirectory: URL

    init() {
        let provider = STTProvider.saved
        self.provider = provider
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel.\(provider.rawValue)")
            ?? Self.defaultModel(for: provider)
        modelsDirectory = Constants.dataDirectory.appendingPathComponent("Models", isDirectory: true)

        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        refreshLocalModels()
    }

    /// Scans for already-downloaded models matching the current provider.
    func refreshLocalModels() {
        let models = Self.availableModels(for: provider)
        availableLocalModels = models.filter { localModelPath(for: $0) != nil }

        if let localPath = localModelPath(for: selectedModel) {
            modelState = .ready(path: localPath)
        } else {
            modelState = .notDownloaded
        }
    }

    /// Returns the local path for a model if it exists, nil otherwise.
    func localModelPath(for model: String) -> String? {
        // For Parakeet, check FluidAudio's cache directory
        if Self.parakeetModels.contains(model) {
            let version: AsrModelVersion = model.contains("v3") ? .v3 : .v2
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            if AsrModels.modelsExist(at: cacheDir, version: version) {
                return cacheDir.path
            }
            return nil
        }

        // For WhisperKit, scan ~/.voxa/Models/
        for dir in findWhisperKitModelDirs() {
            if dir.lastPathComponent == model {
                return dir.path
            }
        }
        return nil
    }

    /// Scans ~/.voxa/Models/ for WhisperKit model directories.
    private func findWhisperKitModelDirs() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let knownModels = Set(Self.whisperKitModels)
        var results: [URL] = []

        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, knownModels.contains(url.lastPathComponent) {
                results.append(url)
            }
        }
        return results
    }

    /// Downloads the selected model.
    func downloadSelectedModel() async {
        await downloadModel(selectedModel)
    }

    /// Downloads a specific model variant.
    func downloadModel(_ variant: String) async {
        guard modelState != .downloading(progress: 0) else { return }
        modelState = .downloading(progress: 0)

        do {
            switch provider {
            case .whisperKit:
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

            case .parakeet:
                let modelFolder = try await downloadParakeetModel(variant)
                modelState = .ready(path: modelFolder.path)
            }

            refreshLocalModels()
            if case .ready(let path) = modelState {
                onModelReady?(path)
            }
            print("[ModelManager] Model downloaded: \(variant)")
        } catch {
            modelState = .error(error.localizedDescription)
            print("[ModelManager] Download failed: \(error)")
        }
    }

    /// Selects a different model. Auto-downloads if not available locally.
    func selectModel(_ variant: String) {
        selectedModel = variant
        UserDefaults.standard.set(variant, forKey: "selectedModel.\(provider.rawValue)")
        if let localPath = localModelPath(for: variant) {
            modelState = .ready(path: localPath)
            onModelReady?(localPath)
        } else {
            Task { await downloadModel(variant) }
        }
    }

    /// Returns the recommended model for this device (WhisperKit only).
    func recommendedModel() -> String {
        guard provider == .whisperKit else { return Self.defaultModel(for: provider) }
        let recommended = WhisperKit.recommendedModels()
        return recommended.default
    }

    // MARK: - Parakeet Download

    /// Downloads a Parakeet model using FluidAudio's built-in downloader.
    private func downloadParakeetModel(_ variant: String) async throws -> URL {
        let version: AsrModelVersion = variant.contains("v3") ? .v3 : .v2

        let cacheDir = try await AsrModels.download(version: version) { [weak self] progress in
            Task { @MainActor in
                self?.modelState = .downloading(progress: progress.fractionCompleted)
            }
        }

        print("[ModelManager] Parakeet model downloaded to: \(cacheDir.path)")
        return cacheDir
    }
}
