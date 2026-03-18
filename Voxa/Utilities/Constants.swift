import Carbon

enum Constants {
    // MARK: - Storage
    /// Root directory for all Voxa data (~/.voxa/)
    static let dataDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voxa", isDirectory: true)

    // MARK: - Audio
    /// Sample rate in Hz for recording (WhisperKit expects 16kHz)
    static let audioSampleRate: Double = 16000
    /// Audio buffer size in frames
    static let audioBufferSize: UInt32 = 1024
    /// Maximum recording duration in seconds (safety cap)
    static let maxRecordingDuration: TimeInterval = 60

    // MARK: - Text Injection
    /// Delay before restoring pasteboard after injection (seconds)
    static let pasteboardRestoreDelay: TimeInterval = 0.3

    // MARK: - Ollama
    /// Default Ollama model for text cleanup
    static let ollamaDefaultModel: String = "llama3.2:3b-instruct-q4_K_M"
    /// Maximum time to wait for Ollama cleanup before falling back to raw transcript
    static let ollamaTimeout: TimeInterval = 0.5
    /// Maximum time to wait for Ollama rewrite in Command Mode (rewrites are more complex)
    static let ollamaRewriteTimeout: TimeInterval = 15.0
}
