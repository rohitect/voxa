import Foundation

/// LLM provider backed by the Google Gemini generateContent API.
struct GeminiProvider: LLMProvider {
    let name = "Gemini"
    let defaultModel = "gemini-3-flash-preview"

    static let apiKeyKeychainKey = "gemini_api_key"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private var apiKey: String? {
        KeychainHelper.load(key: Self.apiKeyKeychainKey)
    }

    var isAvailable: Bool {
        get async {
            apiKey != nil
        }
    }

    // MARK: - Chat (non-streaming)

    func chat(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        timeout: TimeInterval
    ) async throws -> ChatResponse {
        let request = try buildRequest(model: model, messages: messages, tools: tools, stream: false, timeout: timeout)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let candidate = candidates.first,
              let content = candidate["content"] as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        let message = parseContent(content)
        let finishReason = parseFinishReason(candidate["finishReason"] as? String, message: message)
        let usage = parseUsage(json["usageMetadata"] as? [String: Any])

        return ChatResponse(message: message, finishReason: finishReason, usage: usage)
    }

    // MARK: - Chat (streaming)

    func chatStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(model: model, messages: messages, tools: tools, stream: true, timeout: timeout)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                        // Read error body from stream
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        var message: String?
                        if let data = errorBody.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = json["error"] as? [String: Any] {
                            message = error["message"] as? String
                        }
                        throw LLMError.httpError(statusCode: http.statusCode, message: message ?? String(errorBody.prefix(500)))
                    }

                    // Gemini streams as JSON array entries, each line prefixed with data:
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let lineData = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let candidate = candidates.first,
                              let content = candidate["content"] as? [String: Any] else {
                            continue
                        }

                        let parts = content["parts"] as? [[String: Any]] ?? []
                        var deltaContent: String?
                        var deltaToolCalls: [ToolCall]?

                        for part in parts {
                            if let text = part["text"] as? String {
                                deltaContent = (deltaContent ?? "") + text
                            }
                            if let fc = part["functionCall"] as? [String: Any],
                               let name = fc["name"] as? String {
                                let args = fc["args"] as? [String: Any] ?? [:]
                                let argsStr = (try? JSONSerialization.data(withJSONObject: args))
                                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                // Store the full part dict (includes thought_signature alongside functionCall)
                                let call = ToolCall(id: UUID().uuidString, name: name, arguments: argsStr, providerRawCall: part)
                                if deltaToolCalls == nil { deltaToolCalls = [] }
                                deltaToolCalls?.append(call)
                            }
                        }

                        let finishReason = candidate["finishReason"] as? String
                        let chunk = ChatStreamChunk(
                            deltaContent: deltaContent,
                            deltaToolCalls: deltaToolCalls,
                            finishReason: finishReason == "STOP" ? .stop : nil
                        )
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        model: String,
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        stream: Bool,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let apiKey else { throw LLMError.invalidAPIKey }

        let endpoint = stream ? "streamGenerateContent?alt=sse&key=\(apiKey)" : "generateContent?key=\(apiKey)"
        let url = URL(string: "\(baseURL)/\(model):\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        var body: [String: Any] = [
            "contents": buildContents(messages),
        ]

        // Add system instruction if present
        if let systemMsg = messages.first(where: { $0.role == .system }), let text = systemMsg.content {
            body["systemInstruction"] = [
                "parts": [["text": text]]
            ]
        }

        if let tools, !tools.isEmpty {
            body["tools"] = [
                [
                    "functionDeclarations": tools.map { tool in
                        [
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": sanitizeSchemaForGemini(tool.parameters),
                        ] as [String: Any]
                    }
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildContents(_ messages: [ChatMessage]) -> [[String: Any]] {
        // Filter out system messages (handled separately as systemInstruction)
        return messages.compactMap { msg -> [String: Any]? in
            guard msg.role != .system else { return nil }

            let role: String
            switch msg.role {
            case .user, .tool: role = "user"
            case .assistant: role = "model"
            case .system: return nil
            }

            var parts: [[String: Any]] = []

            if let content = msg.content {
                if msg.role == .tool {
                    // Use toolName (actual function name) for Gemini's functionResponse
                    let name = msg.toolName ?? msg.toolCallId ?? "unknown"
                    parts.append([
                        "functionResponse": [
                            "name": name,
                            "response": ["result": content],
                        ]
                    ])
                } else {
                    parts.append(["text": content])
                }
            }

            if let toolCalls = msg.toolCalls {
                for tc in toolCalls {
                    if let rawPart = tc.providerRawCall {
                        if rawPart["functionCall"] != nil {
                            // Full part dict (functionCall + thought_signature) — pass through as-is
                            parts.append(rawPart)
                        } else {
                            // Old format: raw dict is the functionCall itself, wrap it
                            parts.append(["functionCall": rawPart])
                        }
                    } else {
                        // No raw data (e.g. Ollama-originated) — reconstruct
                        let args = (try? JSONSerialization.jsonObject(
                            with: Data(tc.arguments.utf8)
                        )) as? [String: Any] ?? [:]
                        parts.append([
                            "functionCall": ["name": tc.name, "args": args]
                        ])
                    }
                }
            }

            return ["role": role, "parts": parts]
        }
    }

    // MARK: - Response Parsing

    private func parseContent(_ content: [String: Any]) -> ChatMessage {
        let parts = content["parts"] as? [[String: Any]] ?? []
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for part in parts {
            if let text = part["text"] as? String {
                textParts.append(text)
            }
            if let fc = part["functionCall"] as? [String: Any],
               let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                let argsStr = (try? JSONSerialization.data(withJSONObject: args))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                // Store the full part dict (includes thought_signature alongside functionCall)
                toolCalls.append(ToolCall(id: UUID().uuidString, name: name, arguments: argsStr, providerRawCall: part))
            }
        }

        return ChatMessage(
            role: .assistant,
            content: textParts.isEmpty ? nil : textParts.joined(),
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }

    private func parseFinishReason(_ raw: String?, message: ChatMessage) -> ChatResponse.FinishReason? {
        if message.toolCalls != nil { return .toolCalls }
        switch raw {
        case "STOP": return .stop
        case "MAX_TOKENS": return .length
        default: return nil
        }
    }

    private func parseUsage(_ dict: [String: Any]?) -> TokenUsage? {
        guard let dict,
              let prompt = dict["promptTokenCount"] as? Int,
              let completion = dict["candidatesTokenCount"] as? Int,
              let total = dict["totalTokenCount"] as? Int else { return nil }
        return TokenUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
    }

    // MARK: - Gemini Schema Sanitization

    /// Gemini's function calling has strict schema requirements.
    /// Strip unsupported fields and fix common incompatibilities.
    private func sanitizeSchemaForGemini(_ schema: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in schema {
            // Skip fields Gemini doesn't support
            if ["$schema", "additionalProperties", "default", "examples", "title"].contains(key) {
                continue
            }

            if key == "properties", let props = value as? [String: Any] {
                var sanitizedProps: [String: Any] = [:]
                for (propName, propValue) in props {
                    if let propDict = propValue as? [String: Any] {
                        sanitizedProps[propName] = sanitizeSchemaForGemini(propDict)
                    } else {
                        sanitizedProps[propName] = propValue
                    }
                }
                result[key] = sanitizedProps
            } else if key == "items", let items = value as? [String: Any] {
                result[key] = sanitizeSchemaForGemini(items)
            } else {
                result[key] = value
            }
        }

        // Gemini requires "type" on every schema object that has "properties"
        if result["properties"] != nil && result["type"] == nil {
            result["type"] = "object"
        }

        // Gemini requires "items" on array types
        if let type = result["type"] as? String, type == "array", result["items"] == nil {
            result["items"] = ["type": "string"]
        }

        return result
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            var message: String?
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? [String: Any] {
                    message = error["message"] as? String
                }
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw LLMError.invalidAPIKey }
            throw LLMError.httpError(statusCode: http.statusCode, message: message)
        }
    }
}
