import Foundation

/// The result of processing a voice input through the agent pipeline.
struct AgentResponse: Sendable {
    /// Text to display in the agent panel.
    let displayText: String
    /// Text to inject into the active app (nil if no injection needed).
    let injectText: String?
    /// Whether the agent used any tools during processing.
    let usedTools: Bool
    /// Names of tools that were invoked.
    let toolsUsed: [String]

    static func chat(_ text: String) -> AgentResponse {
        AgentResponse(displayText: text, injectText: nil, usedTools: false, toolsUsed: [])
    }

    static func withTools(_ text: String, tools: [String]) -> AgentResponse {
        AgentResponse(displayText: text, injectText: nil, usedTools: true, toolsUsed: tools)
    }

    static func injection(_ text: String, display: String) -> AgentResponse {
        AgentResponse(displayText: display, injectText: text, usedTools: false, toolsUsed: [])
    }
}
