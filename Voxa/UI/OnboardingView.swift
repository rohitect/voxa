import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    var onComplete: () -> Void

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Welcome to Voxa")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)

            Text("Let's set up your offline voice-to-text.")
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            Divider()

            // Steps
            TabView(selection: $currentStep) {
                microphoneStep.tag(0)
                accessibilityStep.tag(1)
                modelStep.tag(2)
                ollamaStep.tag(3)
                readyStep.tag(4)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }
                Spacer()

                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<5) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if currentStep < 4 {
                    Button("Next") { currentStep += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: "onboardingComplete")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 440, height: 380)
        .background(Color.clear)
    }

    // MARK: - Steps

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Microphone Access")
                .font(.headline)

            Text("Voxa needs your microphone to capture speech for transcription. Audio is processed entirely on your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.permissionManager.microphoneGranted ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(appState.permissionManager.microphoneGranted ? "Microphone granted" : "Not yet granted")
                    .font(.caption)
            }

            if !appState.permissionManager.microphoneGranted {
                Button("Grant Microphone Access") {
                    appState.permissionManager.requestMicrophone()
                }
            }
            Spacer()
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Accessibility Permission")
                .font(.headline)

            Text("Required for global hotkeys (Option+Space) and text injection into other apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.permissionManager.accessibilityGranted ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(appState.permissionManager.accessibilityGranted ? "Accessibility granted" : "Not yet granted")
                    .font(.caption)
            }

            if !appState.permissionManager.accessibilityGranted {
                Button("Open Accessibility Settings") {
                    appState.permissionManager.promptAccessibility()
                }
            }
            Spacer()
        }
    }

    private var modelStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(.purple)

            Text("Download Speech Model")
                .font(.headline)

            Text("Voxa uses WhisperKit for on-device transcription. Download a model to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            ModelDownloadView(modelManager: appState.modelManager)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var ollamaStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("LLM Text Cleanup (Optional)")
                .font(.headline)

            Text("Install Ollama to clean up transcriptions with a local LLM. This is optional — Voxa works without it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.textCleanupEngine.ollamaAvailable ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(appState.textCleanupEngine.ollamaAvailable ? "Ollama connected" : "Ollama not detected")
                    .font(.caption)
            }

            Button("Check Ollama Status") {
                Task { await appState.refreshOllamaStatus() }
            }

            Spacer()
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.headline)

            Text("Press and hold **Option+Space** to start dictating. Release to transcribe and paste.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("Push to Talk: Hold to record", systemImage: "hand.tap.fill")
                Label("Flow Mode: Toggle for hands-free", systemImage: "waveform.path")
                Label("Command Mode: Edit highlighted text", systemImage: "text.cursor")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
