import Foundation

/// Push-to-Talk: Hold hotkey → record → release → process → inject.
/// This is the default mode and matches the existing behavior.
final class PushToTalkMode {

    /// Called when the hotkey is pressed down.
    static func onHotkeyDown(appState: AppState) {
        guard appState.status == .idle || appState.status == .processing else { return }
        guard appState.permissionManager.microphoneGranted else {
            print("[PushToTalk] Cannot record — microphone not granted")
            return
        }
        print("[PushToTalk] Hotkey DOWN — starting recording")
        appState.status = .listening
        SoundManager.shared.playStartSound()
        FloatingIndicator.shared.showRecording()
        appState.audioEngine.startRecording()
    }

    /// Called when the hotkey is released.
    static func onHotkeyUp(appState: AppState) {
        guard appState.status == .listening else { return }
        appState.audioEngine.stopRecording()
        SoundManager.shared.playStopSound()
        let buffer = appState.audioEngine.getBufferAndClear()
        print("[PushToTalk] Hotkey UP — captured \(buffer.count) samples")

        guard !buffer.isEmpty else {
            appState.status = .idle
            FloatingIndicator.shared.dismiss()
            return
        }

        processBuffer(buffer, appState: appState)
    }

    /// Transcribes, cleans up, and injects the audio buffer.
    static func processBuffer(_ buffer: [Float], appState: AppState) {
        guard appState.transcriptionEngine.isLoaded else {
            print("[PushToTalk] Transcription model not loaded — skipping")
            appState.status = .idle
            FloatingIndicator.shared.dismiss()
            return
        }

        appState.status = .processing
        FloatingIndicator.shared.showProcessing()

        Task { @MainActor in
            defer { appState.status = .idle }
            do {
                let result = try await appState.transcriptionEngine.transcribe(audioBuffer: buffer)
                print("[PushToTalk] Raw transcription: \"\(result.text)\"")

                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    print("[PushToTalk] Empty transcription — skipping")
                    FloatingIndicator.shared.dismiss()
                    return
                }

                // Check for voice shortcuts first
                if let expansion = ShortcutManager.shared.matchShortcut(in: trimmed) {
                    TextInjector.inject(expansion)
                    appState.lastTranscription = expansion
                    print("[PushToTalk] Voice shortcut matched — injected expansion")
                    FloatingIndicator.shared.showDone()
                    SoundManager.shared.playDoneSound()
                    return
                }

                // LLM cleanup
                var cleanedText = await appState.textCleanupEngine.cleanup(result.text)

                // Apply personal dictionary
                cleanedText = DictionaryManager.shared.apply(to: cleanedText)

                appState.lastTranscription = cleanedText
                TranscriptionHistory.shared.add(text: cleanedText, mode: appState.currentMode.rawValue)
                TextInjector.inject(cleanedText)
                print("[PushToTalk] Final text injected: \"\(cleanedText)\"")

                FloatingIndicator.shared.showDone()
                SoundManager.shared.playDoneSound()
            } catch {
                print("[PushToTalk] Transcription failed: \(error)")
                FloatingIndicator.shared.dismiss()
            }
        }
    }
}
