import AppKit
import SwiftUI

/// Facade for the agent chat UI — now embedded in the companion window.
/// All callers continue using `AgentPanel.shared`; the chat appears inline
/// within the companion orb's panel instead of a separate floating window.
final class AgentPanel {
    static let shared = AgentPanel()

    let state = AgentPanelState()
    private var dismissTimer: Timer?

    private init() {}

    // MARK: - Public API

    /// Show the panel with a listening indicator.
    func showListening() {
        state.isListening = true
        state.isProcessing = false
        state.streamingText = ""
        state.currentToolName = nil
        showPanel()
    }

    /// Show processing state.
    func showProcessing() {
        state.isListening = false
        state.isProcessing = true
        state.streamingText = ""
        state.liveTrace = nil
    }

    /// Append a text delta from the LLM stream.
    func appendStreamingText(_ delta: String) {
        if state.isProcessing {
            state.isProcessing = false
        }
        state.isStreaming = true
        state.streamingText += delta
    }

    /// Show which tool is currently executing.
    func showToolExecution(_ toolName: String) {
        state.currentToolName = toolName
        state.isProcessing = true
        state.isStreaming = false
        state.streamingText = ""
    }

    func clearToolExecution() {
        state.currentToolName = nil
    }

    /// Finalize the response — transition from streaming to committed session history.
    func finalizeResponse(_ response: AgentResponse, session: ChatSession) {
        state.isListening = false
        state.isProcessing = false
        state.isStreaming = false
        state.streamingText = ""
        state.currentToolName = nil
        state.liveTrace = nil
        state.session = session

        if state.panelMode == .popUp {
            scheduleAutoDismiss()
        }
    }

    /// Show a status message (e.g. "Session reset").
    func showStatus(_ message: String) {
        state.isListening = false
        state.isProcessing = false
        state.isStreaming = false
        state.streamingText = ""
        state.currentToolName = nil
        state.statusMessage = message

        if state.panelMode == .popUp {
            scheduleAutoDismiss()
        }
    }

    /// Legacy compatibility — same as finalizeResponse.
    func showResponse(_ response: AgentResponse, session: ChatSession) {
        finalizeResponse(response, session: session)
    }

    /// Show the panel (expand chat from companion).
    func show() {
        showPanel()
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        CompanionWindow.shared.collapseChat()
    }

    func toggle() {
        CompanionWindow.shared.toggleChat()
    }

    // MARK: - Private

    private func showPanel() {
        // Ensure the companion orb is visible, then expand chat from it.
        if !CompanionWindow.shared.isShown {
            CompanionWindow.shared.show()
        }
        if !CompanionState.shared.isChatExpanded {
            CompanionWindow.shared.expandChat()
        }
    }

    private func scheduleAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
}

// MARK: - Panel State

@Observable
final class AgentPanelState {
    var session: ChatSession?
    var isListening = false
    var isProcessing = false
    var isStreaming = false
    var streamingText = ""
    var statusMessage: String?
    var currentToolName: String?
    var toolRegistry: ToolRegistry?

    /// Live trace being built during the current processing turn.
    var liveTrace: MessageTrace?

    /// Persistent or pop-up mode.
    var panelMode: PanelMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "agent.panelMode") ?? "persistent"
            return PanelMode(rawValue: raw) ?? .persistent
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "agent.panelMode")
        }
    }

    /// Callback for new session request from UI.
    var requestNewSession: (() -> Void)?

    /// Callback for sending a typed message.
    var sendMessage: ((String) -> Void)?

    enum PanelMode: String {
        case persistent
        case popUp = "popup"
    }
}
