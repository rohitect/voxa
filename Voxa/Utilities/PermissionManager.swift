import AVFoundation
import ApplicationServices
import AppKit

@Observable
final class PermissionManager {
    var microphoneGranted = false
    var accessibilityGranted = false

    private var accessibilityTimer: Timer?

    init() {
        checkAccessibility()
    }

    // MARK: - Microphone

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                }
            }
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }
    }

    // MARK: - Accessibility

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Checks accessibility silently. Only prompts if explicitly requested by the user.
    func requestAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            startAccessibilityPolling()
        }
    }

    /// Opens System Settings to the Accessibility pane (user-initiated only).
    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted {
            startAccessibilityPolling()
        }
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let trusted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                self.accessibilityGranted = trusted
                if trusted {
                    timer.invalidate()
                    self.accessibilityTimer = nil
                }
            }
        }
    }

    func stopPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }
}
