import Foundation

// MARK: - Chat Role

enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Chat Message

struct ChatMessage: Codable, Sendable {
    let role: ChatRole
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    /// The tool name for tool-result messages (used by Gemini's functionResponse).
    let toolName: String?

    init(role: ChatRole, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil, toolName: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
    }

    enum CodingKeys: String, CodingKey {
        case role, content, toolName
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

// MARK: - Tool Call

struct ToolCall: Codable, Sendable {
    let id: String
    let name: String
    let arguments: String
    /// Provider-specific opaque data (e.g. Gemini's full functionCall dict with thought_signature).
    /// Stored as JSON data for Codable support.
    var providerRawCallData: Data?

    /// Convenience accessor for the raw call dict.
    var providerRawCall: [String: Any]? {
        get {
            guard let data = providerRawCallData else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    init(id: String, name: String, arguments: String, providerRawCall: [String: Any]? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        if let raw = providerRawCall {
            self.providerRawCallData = try? JSONSerialization.data(withJSONObject: raw)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, arguments, providerRawCallData
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]

    /// Convenience initializer from `ToolParameter` array.
    init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name
        self.description = description

        var properties: [String: Any] = [:]
        var required: [String] = []
        for param in parameters {
            var prop: [String: Any] = [
                "type": param.type,
                "description": param.description,
            ]
            if let enumValues = param.enumValues {
                prop["enum"] = enumValues
            }
            properties[param.name] = prop
            if param.required { required.append(param.name) }
        }

        self.parameters = [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
    }

    /// Raw initializer for provider-specific schema dicts.
    init(name: String, description: String, rawParameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = rawParameters
    }
}

// MARK: - Tool Parameter

struct ToolParameter: Sendable {
    let name: String
    let type: String
    let description: String
    let required: Bool
    let enumValues: [String]?

    init(name: String, type: String, description: String, required: Bool = true, enumValues: [String]? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

// MARK: - Chat Response

struct ChatResponse: Sendable {
    let message: ChatMessage
    let finishReason: FinishReason?
    let usage: TokenUsage?

    enum FinishReason: String, Sendable {
        case stop
        case toolCalls = "tool_calls"
        case length
    }
}

// MARK: - Token Usage

struct TokenUsage: Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - Chat Stream Chunk

struct ChatStreamChunk: Sendable {
    let deltaContent: String?
    let deltaToolCalls: [ToolCall]?
    let finishReason: ChatResponse.FinishReason?
}

// MARK: - LLM Error

enum LLMError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case timeout
    case invalidAPIKey
    case modelNotFound(String)
    case providerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from LLM provider"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .timeout:
            return "LLM request timed out"
        case .invalidAPIKey:
            return "Invalid API key"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .providerUnavailable(let name):
            return "Provider unavailable: \(name)"
        }
    }
}
