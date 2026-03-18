import AppKit
import SwiftUI

/// A small always-on-top overlay panel that shows recording/processing/done status.
final class FloatingIndicator {
    static let shared = FloatingIndicator()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorContent>?
    private var dismissTimer: Timer?
    private let indicatorState = FloatingIndicatorState()

    private init() {}

    // MARK: - Public API

    func showRecording() {
        indicatorState.phase = .recording
        showPanel()
    }

    func showProcessing() {
        indicatorState.phase = .processing
    }

    func showDone() {
        indicatorState.phase = .done
        // Auto-dismiss after a short delay
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
    }

    // MARK: - Panel Management

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        positionNearCursor()
        panel?.orderFrontRegardless()
    }

    private func createPanel() {
        let content = FloatingIndicatorContent(state: indicatorState)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 140, height: 40)

        let panel = NSPanel(
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
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func positionNearCursor() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        // Position slightly below and to the right of the cursor
        let origin = NSPoint(
            x: mouseLocation.x + 20,
            y: mouseLocation.y - 50
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - State

@Observable
final class FloatingIndicatorState {
    var phase: IndicatorPhase = .recording
}

enum IndicatorPhase {
    case recording
    case processing
    case done

    var icon: String {
        switch self {
        case .recording: return "mic.fill"
        case .processing: return "hourglass"
        case .done: return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .recording: return "Listening..."
        case .processing: return "Processing..."
        case .done: return "Done"
        }
    }

    var color: Color {
        switch self {
        case .recording: return .red
        case .processing: return .orange
        case .done: return .green
        }
    }
}

// MARK: - SwiftUI Content

struct FloatingIndicatorContent: View {
    let state: FloatingIndicatorState

    var body: some View {
        HStack(spacing: 8) {
            if state.phase == .recording {
                // Pulsing dot for recording
                Circle()
                    .fill(state.phase.color)
                    .frame(width: 10, height: 10)
                    .modifier(PulseModifier())
            } else {
                Image(systemName: state.phase.icon)
                    .foregroundStyle(state.phase.color)
                    .font(.system(size: 14, weight: .medium))
            }

            Text(state.phase.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
