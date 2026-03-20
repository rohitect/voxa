import Foundation

/// LLM provider backed by the OpenAI chat completions API.
struct OpenAIProvider: LLMProvider {
    let name = "OpenAI"
    let defaultModel = "gpt-4o-mini"

    static let apiKeyKeychainKey = "openai_api_key"
    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.baseURL = baseURL
    }

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
        let request = try buildRequest(messages: messages, model: model, tools: tools, stream: false, timeout: timeout)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let messageDict = choice["message"] as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        let message = parseMessage(messageDict)
        let finishReason = parseFinishReason(choice["finish_reason"] as? String)
        let usage = parseUsage(json["usage"] as? [String: Any])

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
                    let request = try buildRequest(messages: messages, model: model, tools: tools, stream: true, timeout: timeout)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try validateHTTPResponse(response, data: nil)

                    // Accumulate tool call deltas by index.
                    // OpenAI sends tool calls incrementally: first chunk has id + name,
                    // subsequent chunks for the same index only have argument fragments.
                    var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let lineData = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first,
                              let delta = choice["delta"] as? [String: Any] else {
                            continue
                        }

                        let content = delta["content"] as? String
                        let finishReason = parseFinishReason(choice["finish_reason"] as? String)

                        // Accumulate tool call deltas by index
                        if let tcDeltas = delta["tool_calls"] as? [[String: Any]] {
                            for tc in tcDeltas {
                                let index = tc["index"] as? Int ?? toolCallAccumulator.count
                                let function = tc["function"] as? [String: Any]

                                if let existing = toolCallAccumulator[index] {
                                    // Append argument fragment to existing entry
                                    let argFragment = function?["arguments"] as? String ?? ""
                                    toolCallAccumulator[index] = (
                                        id: existing.id,
                                        name: existing.name,
                                        arguments: existing.arguments + argFragment
                                    )
                                } else {
                                    // First delta for this index — has id and name
                                    let id = tc["id"] as? String ?? UUID().uuidString
                                    let name = function?["name"] as? String ?? ""
                                    let args = function?["arguments"] as? String ?? ""
                                    toolCallAccumulator[index] = (id: id, name: name, arguments: args)
                                }
                            }
                        }

                        // Yield content deltas immediately for streaming display
                        if content != nil || finishReason != nil {
                            let chunk = ChatStreamChunk(
                                deltaContent: content,
                                deltaToolCalls: nil,
                                finishReason: finishReason
                            )
                            continuation.yield(chunk)
                        }
                    }

                    // Yield accumulated tool calls as a single final chunk
                    if !toolCallAccumulator.isEmpty {
                        let toolCalls = toolCallAccumulator.sorted { $0.key < $1.key }.compactMap { (_, entry) -> ToolCall? in
                            guard !entry.name.isEmpty else { return nil }
                            let args = entry.arguments.isEmpty ? "{}" : entry.arguments
                            return ToolCall(id: entry.id, name: entry.name, arguments: args)
                        }
                        if !toolCalls.isEmpty {
                            let chunk = ChatStreamChunk(
                                deltaContent: nil,
                                deltaToolCalls: toolCalls,
                                finishReason: .toolCalls
                            )
                            continuation.yield(chunk)
                        }
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
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        stream: Bool,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let apiKey else { throw LLMError.invalidAPIKey }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func encodeMessage(_ msg: ChatMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": msg.role.rawValue]
        if let content = msg.content { dict["content"] = content }
        if let toolCalls = msg.toolCalls {
            dict["tool_calls"] = toolCalls.map { tc in
                [
                    "id": tc.id,
                    "type": "function",
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

    // MARK: - Response Parsing

    private func parseMessage(_ dict: [String: Any]) -> ChatMessage {
        let role = ChatRole(rawValue: dict["role"] as? String ?? "assistant") ?? .assistant
        let content = dict["content"] as? String
        let toolCalls = parseToolCallDeltas(dict["tool_calls"] as? [[String: Any]])
        return ChatMessage(role: role, content: content, toolCalls: toolCalls)
    }

    private func parseToolCallDeltas(_ array: [[String: Any]]?) -> [ToolCall]? {
        guard let array, !array.isEmpty else { return nil }
        return array.compactMap { tc in
            guard let function = tc["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            let id = tc["id"] as? String ?? UUID().uuidString
            let arguments = function["arguments"] as? String ?? "{}"
            return ToolCall(id: id, name: name, arguments: arguments)
        }
    }

    private func parseFinishReason(_ raw: String?) -> ChatResponse.FinishReason? {
        guard let raw else { return nil }
        switch raw {
        case "stop": return .stop
        case "tool_calls": return .toolCalls
        case "length": return .length
        default: return nil
        }
    }

    private func parseUsage(_ dict: [String: Any]?) -> TokenUsage? {
        guard let dict,
              let prompt = dict["prompt_tokens"] as? Int,
              let completion = dict["completion_tokens"] as? Int,
              let total = dict["total_tokens"] as? Int else { return nil }
        return TokenUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
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
            if http.statusCode == 401 { throw LLMError.invalidAPIKey }
            throw LLMError.httpError(statusCode: http.statusCode, message: message)
        }
    }
}
