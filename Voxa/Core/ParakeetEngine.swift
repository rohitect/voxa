import Foundation
import FluidAudio

/// Wraps FluidAudio's AsrManager to transcribe PCM audio buffers using NVIDIA Parakeet models.
@Observable
final class ParakeetEngine {
    struct Result {
        let text: String
        let segments: [Segment]
        let language: String
        let duration: TimeInterval

        struct Segment {
            let text: String
            let start: Float
            let end: Float
        }
    }

    private let asrManager = AsrManager()
    private(set) var isLoaded = false
    var language: String? = "en"

    /// The model version currently loaded.
    private var loadedVersion: AsrModelVersion = .v2

    /// Loads Parakeet CoreML models from a local directory or the default cache.
    func loadModel(from folderPath: String, version: AsrModelVersion = .v2) async throws {
        print("[ParakeetEngine] Loading model from: \(folderPath)")

        let directory = URL(fileURLWithPath: folderPath, isDirectory: true)
        let models = try await AsrModels.load(from: directory, version: version)
        try await asrManager.initialize(models: models)
        loadedVersion = version
        isLoaded = true

        print("[ParakeetEngine] Model loaded successfully (version: \(version))")
    }

    /// Downloads and loads the Parakeet model from HuggingFace cache.
    func downloadAndLoad(version: AsrModelVersion = .v2, progressHandler: DownloadUtils.ProgressHandler? = nil) async throws {
        print("[ParakeetEngine] Downloading and loading model (version: \(version))")

        let models = try await AsrModels.downloadAndLoad(version: version, progressHandler: progressHandler)
        try await asrManager.initialize(models: models)
        loadedVersion = version
        isLoaded = true

        print("[ParakeetEngine] Model downloaded and loaded successfully")
    }

    /// Unloads the current model to free memory.
    func unloadModel() {
        asrManager.cleanup()
        isLoaded = false
        print("[ParakeetEngine] Model unloaded")
    }

    /// Transcribes a PCM Float32 audio buffer (16kHz mono).
    func transcribe(audioBuffer: [Float]) async throws -> Result {
        guard isLoaded else {
            throw ParakeetError.modelNotLoaded
        }

        guard !audioBuffer.isEmpty else {
            throw ParakeetError.emptyAudio
        }

        let sampleCount = audioBuffer.count
        let audioDuration = Double(sampleCount) / Constants.audioSampleRate
        print("[ParakeetEngine] Transcribing \(sampleCount) samples (\(String(format: "%.1f", audioDuration))s)")

        let asrResult = try await asrManager.transcribe(audioBuffer, source: .microphone)

        // Convert token timings to segments if available
        let segments: [Result.Segment]
        if let timings = asrResult.tokenTimings {
            segments = timings.map { timing in
                Result.Segment(
                    text: timing.token,
                    start: Float(timing.startTime),
                    end: Float(timing.endTime)
                )
            }
        } else {
            segments = []
        }

        let result = Result(
            text: asrResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            language: language ?? "en",
            duration: asrResult.processingTime
        )

        print("[ParakeetEngine] Result (\(String(format: "%.2f", asrResult.processingTime))s): \"\(result.text)\"")
        print("[ParakeetEngine] RTFx: \(String(format: "%.1f", asrResult.rtfx))x real-time")

        return result
    }

    /// Checks if models exist in the default cache directory.
    static func modelsExist(version: AsrModelVersion = .v2) -> Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }
}

enum ParakeetError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Parakeet model is not loaded"
        case .emptyAudio: "Audio buffer is empty"
        }
    }
}
