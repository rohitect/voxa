import Foundation

/// Cleans up raw transcription text using a local LLM via Ollama.
/// Falls back to the raw transcript if Ollama is unavailable or too slow.
@Observable
final class TextCleanupEngine {
    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ollamaCleanupEnabled")
        }
    }
    var ollamaAvailable: Bool = false
    var modelReady: Bool = false
    var modelDownloadStatus: ModelDownloadStatus = .idle

    enum ModelDownloadStatus: Equatable {
        case idle
        case downloading(status: String)
        case failed(message: String)
    }

    private let requiredModel = Constants.ollamaDefaultModel
    private let client: OllamaClient
    private let timeout: TimeInterval

    init(
        client: OllamaClient = OllamaClient(),
        timeout: TimeInterval = Constants.ollamaTimeout
    ) {
        self.client = client
        self.timeout = timeout
        self.isEnabled = UserDefaults.standard.object(forKey: "ollamaCleanupEnabled") as? Bool ?? true
    }

    // MARK: - Status

    /// Checks Ollama availability and whether the required model is downloaded.
    func refreshStatus() async {
        let available = await client.isAvailable()
        let models = available ? await client.listModels() : []
        let hasModel = models.contains { $0.hasPrefix(requiredModel.split(separator: ":").first.map(String.init) ?? requiredModel) || $0 == requiredModel }
        await MainActor.run {
            self.ollamaAvailable = available
            self.modelReady = hasModel
        }
        if available {
            print("[TextCleanup] Ollama available — model \(requiredModel) \(hasModel ? "ready" : "not found")")
        } else {
            print("[TextCleanup] Ollama not available")
        }
    }

    // MARK: - Model Download

    /// Pulls the required model via Ollama.
    func downloadModel() async {
        guard ollamaAvailable else { return }

        await MainActor.run {
            self.modelDownloadStatus = .downloading(status: "Starting download...")
        }

        do {
            try await client.pullModel(name: requiredModel) { status in
                Task { @MainActor in
                    self.modelDownloadStatus = .downloading(status: status)
                }
            }
            await MainActor.run {
                self.modelReady = true
                self.modelDownloadStatus = .idle
            }
            print("[TextCleanup] Model \(requiredModel) downloaded successfully")
        } catch {
            await MainActor.run {
                self.modelDownloadStatus = .failed(message: error.localizedDescription)
            }
            print("[TextCleanup] Model download failed: \(error)")
        }
    }

    // MARK: - Cleanup

    /// Cleans up the raw transcript. Returns the cleaned text, or the original if cleanup
    /// is disabled, Ollama is unavailable, or the request times out.
    func cleanup(_ rawTranscript: String) async -> String {
        guard isEnabled else {
            print("[TextCleanup] Cleanup disabled — using raw transcript")
            return rawTranscript
        }

        guard ollamaAvailable, modelReady else {
            print("[TextCleanup] Ollama unavailable or model not ready — using raw transcript")
            return rawTranscript
        }

        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawTranscript }

        let prompt = buildPrompt(for: trimmed)

        do {
            let cleaned = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.client.generate(
                        model: self.requiredModel,
                        prompt: prompt,
                        timeout: self.timeout
                    )
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(self.timeout))
                    throw OllamaError.timeout
                }

                // Return whichever finishes first; if the timeout fires first, it throws
                guard let result = try await group.next() else {
                    throw OllamaError.timeout
                }
                group.cancelAll()
                return result
            }

            let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty {
                print("[TextCleanup] LLM returned empty — using raw transcript")
                return rawTranscript
            }

            print("[TextCleanup] \"\(trimmed)\" → \"\(result)\"")
            return result
        } catch {
            print("[TextCleanup] Cleanup failed (\(error.localizedDescription)) — using raw transcript")
            return rawTranscript
        }
    }

    // MARK: - Rewrite (Command Mode)

    /// Rewrites text according to a spoken command using the LLM.
    /// Returns the original text if Ollama is unavailable or the request fails.
    func rewrite(text: String, command: String) async -> String {
        guard ollamaAvailable, modelReady else {
            print("[TextCleanup] Ollama unavailable — cannot rewrite")
            return text
        }

        let prompt = """
        Rewrite the following text according to the instruction. \
        Output ONLY the rewritten text, nothing else.

        Text: \(text)

        Instruction: \(command)
        """

        do {
            let result = try await client.generate(
                model: requiredModel,
                prompt: prompt,
                timeout: Constants.ollamaRewriteTimeout
            )
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                print("[TextCleanup] LLM returned empty rewrite — returning original")
                return text
            }
            print("[TextCleanup] Rewrite: \"\(text.prefix(40))...\" → \"\(trimmed.prefix(40))...\"")
            return trimmed
        } catch {
            print("[TextCleanup] Rewrite failed: \(error.localizedDescription) — returning original")
            return text
        }
    }

    // MARK: - Prompt

    private func buildPrompt(for text: String) -> String {
        """
        Clean up this dictated text. Remove filler words (um, uh, like), \
        fix grammar, add proper punctuation (periods, commas, question marks, \
        exclamation marks). Questions must end with a question mark. \
        Keep the meaning exactly the same. \
        Output ONLY the cleaned text, nothing else.

        Input: \(text)
        """
    }
}
