import AppKit
import Carbon

/// Command Mode: User highlights text in any app → presses hotkey → speaks a command.
/// The highlighted text is read via Cmd+C, sent to the LLM along with the spoken command,
/// and the result replaces the highlighted text.
final class CommandMode {

    /// Called when the hotkey is pressed — grab highlighted text, then start recording the command.
    static func onHotkeyDown(appState: AppState) {
        guard appState.status == .idle || appState.status == .processing else { return }
        guard appState.permissionManager.microphoneGranted else {
            print("[CommandMode] Cannot record — microphone not granted")
            return
        }
        guard appState.transcriptionEngine.isLoaded else {
            print("[CommandMode] Transcription model not loaded")
            return
        }

        appState.status = .listening
        FloatingIndicator.shared.showRecording()

        // Step 1: Simulate Cmd+C to grab highlighted text
        simulateCopy()

        // Step 2: After a delay (let the target app process the copy), read pasteboard and start recording
        let previousChangeCount = NSPasteboard.general.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != previousChangeCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                _capturedText = text
                print("[CommandMode] Captured highlighted text: \"\(text.prefix(80))\"")
            } else {
                _capturedText = nil
                print("[CommandMode] No highlighted text found — will treat as regular dictation")
            }

            SoundManager.shared.playStartSound()
            appState.audioEngine.startRecording()
        }
    }

    /// Called when the hotkey is released — transcribe command, send to LLM with highlighted text.
    static func onHotkeyUp(appState: AppState) {
        guard appState.status == .listening else { return }
        appState.audioEngine.stopRecording()
        SoundManager.shared.playStopSound()
        let buffer = appState.audioEngine.getBufferAndClear()

        let highlightedText = _capturedText
        _capturedText = nil

        guard !buffer.isEmpty else {
            appState.status = .idle
            FloatingIndicator.shared.dismiss()
            return
        }

        // If no highlighted text, fall back to push-to-talk behavior
        guard let highlighted = highlightedText, !highlighted.isEmpty else {
            PushToTalkMode.processBuffer(buffer, appState: appState)
            return
        }

        appState.status = .processing
        FloatingIndicator.shared.showProcessing()

        Task { @MainActor in
            defer { appState.status = .idle }
            do {
                let result = try await appState.transcriptionEngine.transcribe(audioBuffer: buffer)
                let command = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !command.isEmpty else {
                    print("[CommandMode] Empty command — skipping")
                    FloatingIndicator.shared.dismiss()
                    return
                }

                print("[CommandMode] Command: \"\(command)\"")

                // Send to LLM: rewrite the highlighted text per the spoken command
                let rewritten = await appState.textCleanupEngine.rewrite(
                    text: highlighted,
                    command: command
                )

                appState.lastTranscription = rewritten
                TextInjector.inject(rewritten)
                print("[CommandMode] Rewritten text injected: \"\(rewritten.prefix(80))\"")

                FloatingIndicator.shared.showDone()
                SoundManager.shared.playDoneSound()
            } catch {
                print("[CommandMode] Failed: \(error)")
                FloatingIndicator.shared.dismiss()
            }
        }
    }

    // MARK: - Private

    private static var _capturedText: String?

    private static func simulateCopy() {
        let cKeyCode = UInt16(kVK_ANSI_C)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: cKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

}
