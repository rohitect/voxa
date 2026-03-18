import Foundation

/// LLM provider backed by a local Ollama instance.
struct OllamaProvider: LLMProvider {
    let name = "Ollama"
    let defaultModel = "llama3.2:3b-instruct-q4_K_M"

    private let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    var isAvailable: Bool {
        get async {
            let url = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    // MARK: - Chat (non-streaming)

    func chat(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        timeout: TimeInterval
    ) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body = buildRequestBody(messages: messages, model: model, tools: tools, stream: false)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageDict = json["message"] as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        return parseResponse(messageDict: messageDict)
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
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = timeout

                    let body = buildRequestBody(messages: messages, model: model, tools: tools, stream: true)
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try validateHTTPResponse(response)

                    for try await line in bytes.lines {
                        guard let lineData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let messageDict = json["message"] as? [String: Any] else {
                            continue
                        }

                        let content = messageDict["content"] as? String
                        let done = json["done"] as? Bool ?? false

                        let toolCalls = parseToolCalls(from: messageDict)

                        let chunk = ChatStreamChunk(
                            deltaContent: content,
                            deltaToolCalls: toolCalls,
                            finishReason: done ? .stop : nil
                        )
                        continuation.yield(chunk)

                        if done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { encodeMessage($0) },
            "stream": stream,
        ]

        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters,
                    ] as [String: Any],
                ] as [String: Any]
            }
        }

        return body
    }

    private func encodeMessage(_ msg: ChatMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": msg.role.rawValue]
        if let content = msg.content { dict["content"] = content }
        if let toolCalls = msg.toolCalls {
            dict["tool_calls"] = toolCalls.map { tc in
                [
                    "id": tc.id,
                    "function": [
                        "name": tc.name,
                        "arguments": tc.arguments,
                    ],
                ] as [String: Any]
            }
        }
        if let toolCallId = msg.toolCallId { dict["tool_call_id"] = toolCallId }
        return dict
    }

    private func parseResponse(messageDict: [String: Any]) -> ChatResponse {
        let role = ChatRole(rawValue: messageDict["role"] as? String ?? "assistant") ?? .assistant
        let content = messageDict["content"] as? String
        let toolCalls = parseToolCalls(from: messageDict)

        let message = ChatMessage(
            role: role,
            content: content,
            toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls
        )

        let finishReason: ChatResponse.FinishReason? = toolCalls != nil ? .toolCalls : .stop

        return ChatResponse(message: message, finishReason: finishReason, usage: nil)
    }

    private func parseToolCalls(from messageDict: [String: Any]) -> [ToolCall]? {
        guard let toolCallsArray = messageDict["tool_calls"] as? [[String: Any]] else { return nil }
        return toolCallsArray.compactMap { tc in
            guard let function = tc["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }

            let id = tc["id"] as? String ?? UUID().uuidString
            let arguments: String
            if let argsDict = function["arguments"] as? [String: Any],
               let argsData = try? JSONSerialization.data(withJSONObject: argsDict) {
                arguments = String(data: argsData, encoding: .utf8) ?? "{}"
            } else if let argsStr = function["arguments"] as? String {
                arguments = argsStr
            } else {
                arguments = "{}"
            }
            return ToolCall(id: id, name: name, arguments: arguments)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw LLMError.httpError(statusCode: http.statusCode, message: nil)
        }
    }
}
