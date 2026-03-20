import AppKit
import SwiftUI

/// A tiny always-on-top NSPanel hosting the floating companion orb.
/// The panel is always sized large enough for orb + chat. When collapsed,
/// the chat area is hidden and clicks pass through the empty region.
final class CompanionWindow {
    static let shared = CompanionWindow()

    private var panel: CompanionPanel?
    private var hostingView: HitTestHostingView<CompanionView>?

    /// The full panel size (always this size — SwiftUI handles showing/hiding chat).
    private let panelSize = NSSize(width: 380, height: 540)
    /// Orb-only area for hit testing (top-center of the panel).
    private let orbSize = NSSize(width: 140, height: 120)

    private init() {}

    // MARK: - Public API

    var panelFrame: NSRect {
        panel?.frame ?? .zero
    }

    var isShown: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        restorePosition()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Expand the companion panel to show the inline chat.
    func expandChat() {
        guard let panel else { return }
        // Enable hit testing on the full panel
        hostingView?.chatExpanded = true
        CompanionState.shared.isChatExpanded = true
        panel.makeKey()
    }

    /// Collapse the chat back to just the orb.
    func collapseChat() {
        guard CompanionState.shared.isChatExpanded else { return }
        // SwiftUI animation will hide the chat; restrict hit testing to orb area
        CompanionState.shared.isChatExpanded = false
        hostingView?.chatExpanded = false
    }

    func toggleChat() {
        if CompanionState.shared.isChatExpanded {
            collapseChat()
        } else {
            expandChat()
        }
    }

    /// Reset position to default (bottom-right) and show.
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "companion.posX")
        UserDefaults.standard.removeObject(forKey: "companion.posY")
        if let panel {
            panel.setFrameOrigin(defaultPosition())
        }
    }

    // MARK: - Panel Management

    private func createPanel() {
        let content = CompanionView(
            panelState: AgentPanel.shared.state,
            onDismissChat: { [weak self] in
                self?.collapseChat()
            },
            onNewSession: {
                AgentPanel.shared.state.requestNewSession?()
            }
        )
        let hostingView = HitTestHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        // Define the orb hit-test rect: top-center of the panel
        let orbRect = NSRect(
            x: (panelSize.width - orbSize.width) / 2,
            y: panelSize.height - orbSize.height,
            width: orbSize.width,
            height: orbSize.height
        )
        hostingView.orbRect = orbRect
        hostingView.chatExpanded = false

        let panel = CompanionPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView

        // Persist position when drag ends
        panel.onDragEnd = {
            self.persistPosition()
        }

        self.panel = panel
        self.hostingView = hostingView
    }

    private func restorePosition() {
        guard let panel else { return }

        let hasStored = UserDefaults.standard.object(forKey: "companion.posX") != nil
        if hasStored {
            let x = UserDefaults.standard.double(forKey: "companion.posX")
            let y = UserDefaults.standard.double(forKey: "companion.posY")
            let origin = NSPoint(x: x, y: y)
            if isOnScreen(origin) {
                panel.setFrameOrigin(origin)
                return
            }
        }
        panel.setFrameOrigin(defaultPosition())
    }

    private func persistPosition() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(Double(frame.origin.x), forKey: "companion.posX")
        UserDefaults.standard.set(Double(frame.origin.y), forKey: "companion.posY")
    }

    private func defaultPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let screenFrame = screen.visibleFrame
        return NSPoint(
            x: screenFrame.maxX - panelSize.width - 20,
            y: screenFrame.minY + 60
        )
    }

    private func isOnScreen(_ origin: NSPoint) -> Bool {
        // Check using just the orb area at the top of the panel
        let orbOrigin = NSPoint(
            x: origin.x + (panelSize.width - orbSize.width) / 2,
            y: origin.y + panelSize.height - orbSize.height
        )
        let rect = NSRect(origin: orbOrigin, size: orbSize)
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(rect) {
                return true
            }
        }
        return false
    }
}

// MARK: - Hit-Test Hosting View

/// Custom NSHostingView that passes clicks through the empty area when
/// the chat is collapsed — only the orb region is interactive.
final class HitTestHostingView<Content: View>: NSHostingView<Content> {
    /// The rect of the orb within the view (in view coordinates).
    var orbRect: NSRect = .zero
    /// Whether the chat panel is expanded (full hit testing) or collapsed (orb only).
    var chatExpanded = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if chatExpanded {
            return super.hitTest(point)
        }
        // Collapsed: only the orb area is hittable
        if orbRect.contains(point) {
            return super.hitTest(point)
        }
        return nil // Click passes through to app behind
    }
}

// MARK: - Custom NSPanel subclass for drag detection

final class CompanionPanel: NSPanel {
    var onDragEnd: (() -> Void)?
    private var isDragging = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        if CompanionState.shared.isChatExpanded {
            CompanionWindow.shared.collapseChat()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnd?()
            isDragging = false
        } else {
            CompanionWindow.shared.toggleChat()
        }
        super.mouseUp(with: event)
    }
}
