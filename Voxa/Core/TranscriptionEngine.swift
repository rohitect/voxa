import Foundation
import WhisperKit

/// Wraps WhisperKit to transcribe PCM audio buffers into text.
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
    private(set) var isLoaded = false
    var language: String? = "en" // nil = auto-detect

    /// Loads the WhisperKit model from a local folder path.
    func loadModel(from folderPath: String) async throws {
        print("[TranscriptionEngine] Loading model from: \(folderPath)")

        let config = WhisperKitConfig(
            modelFolder: folderPath,
            computeOptions: ModelComputeOptions(),
            download: false
        )
        whisperKit = try await WhisperKit(config)
        isLoaded = true

        print("[TranscriptionEngine] Model loaded successfully")
    }

    /// Unloads the current model to free memory.
    func unloadModel() {
        whisperKit = nil
        isLoaded = false
        print("[TranscriptionEngine] Model unloaded")
    }

    /// Transcribes a PCM Float32 audio buffer (16kHz mono).
    func transcribe(audioBuffer: [Float]) async throws -> Result {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !audioBuffer.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let sampleCount = audioBuffer.count
        let audioDuration = Double(sampleCount) / Constants.audioSampleRate
        print("[TranscriptionEngine] Transcribing \(sampleCount) samples (\(String(format: "%.1f", audioDuration))s)")

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
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "WhisperKit model is not loaded"
        case .emptyAudio: "Audio buffer is empty"
        }
    }
}
