import Foundation

/// Observable state driving the floating companion's animations.
@Observable
final class CompanionState {
    static let shared = CompanionState()

    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case responding
        case toolExecution(String)
    }

    var phase: Phase = .idle

    /// Incremented on each streaming delta — drives response glow animation.
    var tokenPulseCounter: Int = 0

    // MARK: - Inline Indicator (replaces separate FloatingIndicator panel)

    enum IndicatorPhase: Equatable {
        case hidden
        case recording
        case processing
        case done
    }

    var indicatorPhase: IndicatorPhase = .hidden
    private var dismissWork: DispatchWorkItem?

    func showIndicator(_ phase: IndicatorPhase) {
        dismissWork?.cancel()
        dismissWork = nil
        indicatorPhase = phase

        if phase == .done {
            let work = DispatchWorkItem { [weak self] in
                self?.indicatorPhase = .hidden
            }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    func dismissIndicator() {
        dismissWork?.cancel()
        dismissWork = nil
        indicatorPhase = .hidden
    }

    /// Whether the inline chat panel is expanded from the companion orb.
    var isChatExpanded = false

    /// Whether the companion orb is visible. Stored property so @Observable can track it.
    var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: "companion.visible") }
    }

    private init() {
        // Default to visible on first launch
        if UserDefaults.standard.object(forKey: "companion.visible") == nil {
            UserDefaults.standard.set(true, forKey: "companion.visible")
        }
        self.isVisible = UserDefaults.standard.bool(forKey: "companion.visible")
    }
}
