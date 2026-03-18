import Foundation

/// HTTP client for communicating with the Ollama local API.
final class OllamaClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let downloadSession: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        // Separate session for long-running downloads (model pulls)
        let downloadConfig = URLSessionConfiguration.default
        downloadConfig.timeoutIntervalForRequest = 300
        downloadConfig.timeoutIntervalForResource = 3600
        self.downloadSession = URLSession(configuration: downloadConfig)
    }

    // MARK: - Health Check

    /// Checks if Ollama is running and reachable.
    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Returns the list of locally available model names.
    func listModels() async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            return decoded.models.map(\.name)
        } catch {
            return []
        }
    }

    // MARK: - Pull Model

    /// Pulls (downloads) a model via Ollama. Calls `onProgress` with status strings as they stream in.
    /// Ollama streams JSON lines with `{"status": "..."}` during pull.
    func pullModel(name: String, onProgress: @escaping @Sendable (String) -> Void) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600 // models can be large

        let body = try JSONEncoder().encode(["name": name])
        request.httpBody = body

        let (bytes, response) = try await downloadSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONDecoder().decode(PullProgress.self, from: data) else {
                continue
            }
            onProgress(json.status)
        }
    }

    // MARK: - Generate

    /// Sends a prompt to the Ollama `/api/generate` endpoint and returns the full response text.
    /// Uses non-streaming mode for simplicity.
    func generate(model: String, prompt: String, timeout: TimeInterval) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body = GenerateRequest(model: model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response
    }
}

// MARK: - Request/Response Types

private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct GenerateResponse: Decodable {
    let response: String
}

private struct PullProgress: Decodable {
    let status: String
}

private struct TagsResponse: Decodable {
    let models: [ModelInfo]

    struct ModelInfo: Decodable {
        let name: String
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama"
        case .httpError(let code):
            return "Ollama returned HTTP \(code)"
        case .timeout:
            return "Ollama request timed out"
        }
    }
}
