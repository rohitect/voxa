import AppKit
import SwiftUI

/// A floating panel that displays the agent's chat interface.
/// Supports two modes: persistent (stays open) and pop-up (auto-dismisses).
final class AgentPanel {
    static let shared = AgentPanel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?
    let state = AgentPanelState()

    private init() {}

    // MARK: - Public API

    /// Show the panel with a listening indicator.
    func showListening() {
        state.isListening = true
        state.isProcessing = false
        showPanel()
    }

    /// Show processing state.
    func showProcessing() {
        state.isListening = false
        state.isProcessing = true
    }

    /// Show a response in the panel.
    func showResponse(_ response: AgentResponse, session: ChatSession) {
        state.isListening = false
        state.isProcessing = false
        state.session = session

        if state.panelMode == .popUp {
            scheduleAutoDismiss()
        }
    }

    /// Show a status message (e.g. "Session reset").
    func showStatus(_ message: String) {
        state.isListening = false
        state.isProcessing = false
        state.statusMessage = message

        if state.panelMode == .popUp {
            scheduleAutoDismiss()
        }
    }

    /// Show tool execution status.
    func showToolExecution(_ toolName: String) {
        state.currentToolName = toolName
    }

    func clearToolExecution() {
        state.currentToolName = nil
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            showPanel()
        }
    }

    // MARK: - Panel Management

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        updatePanelSize()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func createPanel() {
        let content = AgentPanelContent(state: state, onDismiss: { [weak self] in
            self?.dismiss()
        }, onNewSession: { [weak self] in
            self?.state.requestNewSession?()
        })
        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Voxa Agent"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        panel.minSize = NSSize(width: 300, height: 200)

        self.panel = panel
    }

    private func updatePanelSize() {
        guard let panel else { return }
        let size: NSSize = state.panelMode == .persistent
            ? NSSize(width: 400, height: 500)
            : NSSize(width: 340, height: 240)
        panel.setContentSize(size)
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        // Position in the top-right corner of the screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - panel.frame.width - 20
        let y = screenFrame.maxY - panel.frame.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
    var statusMessage: String?
    var currentToolName: String?

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

    enum PanelMode: String {
        case persistent
        case popUp = "popup"
    }
}
