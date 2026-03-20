import Foundation

/// Facade that delegates indicator display to the companion orb's inline pill.
/// All callers continue using `FloatingIndicator.shared` — the indicator now
/// appears attached to the floating companion character and moves with it.
final class FloatingIndicator {
    static let shared = FloatingIndicator()

    private let companion = CompanionState.shared

    private init() {}

    func showRecording() {
        companion.showIndicator(.recording)
    }

    func showProcessing() {
        companion.showIndicator(.processing)
    }

    func showDone() {
        companion.showIndicator(.done)
    }

    func dismiss() {
        companion.dismissIndicator()
    }
}
