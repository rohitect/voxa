import Foundation
import FluidAudio
import WhisperKit

/// Unified transcription facade that delegates to WhisperKit or Parakeet.
@Observable
final class TranscriptionEngine {
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

    private var whisperKit: WhisperKit?
    private let parakeetEngine = ParakeetEngine()

    private(set) var isLoaded = false
    var language: String? = "en" // nil = auto-detect
    var provider: STTProvider = STTProvider.saved {
        didSet { STTProvider.saved = provider }
    }

    /// Loads the model for the current provider from a local folder path.
    func loadModel(from folderPath: String) async throws {
        // Unload any existing model first
        unloadModel()

        switch provider {
        case .whisperKit:
            try await loadWhisperKit(from: folderPath)
        case .parakeet:
            try await loadParakeet(from: folderPath)
        }
        isLoaded = true
    }

    /// Unloads the current model to free memory.
    func unloadModel() {
        whisperKit = nil
        parakeetEngine.unloadModel()
        isLoaded = false
        print("[TranscriptionEngine] Model unloaded")
    }

    /// Transcribes a PCM Float32 audio buffer (16kHz mono).
    func transcribe(audioBuffer: [Float]) async throws -> Result {
        guard isLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !audioBuffer.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        switch provider {
        case .whisperKit:
            return try await transcribeWithWhisperKit(audioBuffer: audioBuffer)
        case .parakeet:
            return try await transcribeWithParakeet(audioBuffer: audioBuffer)
        }
    }

    // MARK: - WhisperKit Backend

    private func loadWhisperKit(from folderPath: String) async throws {
        print("[TranscriptionEngine] Loading WhisperKit model from: \(folderPath)")
        let config = WhisperKitConfig(
            modelFolder: folderPath,
            computeOptions: ModelComputeOptions(),
            download: false
        )
        whisperKit = try await WhisperKit(config)
        print("[TranscriptionEngine] WhisperKit model loaded successfully")
    }

    private func transcribeWithWhisperKit(audioBuffer: [Float]) async throws -> Result {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let sampleCount = audioBuffer.count
        let audioDuration = Double(sampleCount) / Constants.audioSampleRate
        print("[TranscriptionEngine] Transcribing \(sampleCount) samples (\(String(format: "%.1f", audioDuration))s) [WhisperKit]")

        let options = DecodingOptions(
            language: language,
            temperature: 0.0,
            chunkingStrategy: audioDuration > 30 ? .vad : nil
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        let results = try await whisperKit.transcribe(
            audioArray: audioBuffer,
            decodeOptions: options
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let first = results.first else {
            return Result(text: "", segments: [], language: language ?? "unknown", duration: elapsed)
        }

        let segments = first.segments.map { seg in
            Result.Segment(text: seg.text, start: seg.start, end: seg.end)
        }

        let result = Result(
            text: first.text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            language: first.language,
            duration: elapsed
        )

        print("[TranscriptionEngine] Result (\(String(format: "%.2f", elapsed))s): \"\(result.text)\"")
        let timings = first.timings
        print("[TranscriptionEngine] Speed: \(String(format: "%.1f", timings.tokensPerSecond)) tokens/s, RTF: \(String(format: "%.2f", timings.realTimeFactor))")

        return result
    }

    // MARK: - Parakeet Backend

    private func loadParakeet(from folderPath: String) async throws {
        parakeetEngine.language = language
        // Determine version from the folder path
        let version: AsrModelVersion = folderPath.contains("v3") ? .v3 : .v2
        try await parakeetEngine.loadModel(from: folderPath, version: version)
    }

    private func transcribeWithParakeet(audioBuffer: [Float]) async throws -> Result {
        parakeetEngine.language = language
        let parakeetResult = try await parakeetEngine.transcribe(audioBuffer: audioBuffer)
        return Result(
            text: parakeetResult.text,
            segments: parakeetResult.segments.map { seg in
                Result.Segment(text: seg.text, start: seg.start, end: seg.end)
            },
            language: parakeetResult.language,
            duration: parakeetResult.duration
        )
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Transcription model is not loaded"
        case .emptyAudio: "Audio buffer is empty"
        }
    }
}
