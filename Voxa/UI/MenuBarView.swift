import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Binding var showSettings: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status row
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.status.displayText)
                    .font(.system(.body, design: .rounded))
            }
            .padding(.horizontal, 4)

            // Last transcription
            if let text = appState.lastTranscription {
                Divider()
                Text(text)
                    .font(.caption)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
                    .foregroundStyle(.secondary)
            }

            // Hotkeys
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                hotkeyRow(icon: "hand.tap.fill", label: "Talk", binding: appState.hotkeyManager.pushToTalkBinding)
                hotkeyRow(icon: "waveform.path", label: "Flow", binding: appState.hotkeyManager.flowBinding)
                hotkeyRow(icon: "text.cursor", label: "Command", binding: appState.hotkeyManager.commandBinding)
            }
            .padding(.horizontal, 4)

            // Model status
            Divider()
            ModelDownloadView(modelManager: appState.modelManager)
                .padding(.horizontal, 4)

            // Permission warnings
            if !appState.permissionManager.accessibilityGranted {
                Divider()
                HStack {
                    Label("Accessibility not granted", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Spacer()
                    Button("Grant") {
                        appState.permissionManager.promptAccessibility()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 4)
            }

            if !appState.permissionManager.microphoneGranted {
                if appState.permissionManager.accessibilityGranted {
                    Divider()
                }
                Label("Microphone not granted", systemImage: "mic.slash.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.horizontal, 4)
            }

            // Ollama status
            Divider()
            ollamaStatusSection
                .padding(.horizontal, 4)

            Divider()

            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Button("Quit Voxa") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }

    @ViewBuilder
    private var ollamaStatusSection: some View {
        let engine = appState.textCleanupEngine

        if !engine.ollamaAvailable {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Ollama not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if engine.modelReady {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("LLM cleanup ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("LLM Cleanup", isOn: Bindable(engine).isEnabled)
                .font(.caption)
        } else {
            switch engine.modelDownloadStatus {
            case .idle:
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("LLM model not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Download LLM Model") {
                    Task { await engine.downloadModel() }
                }
                .font(.caption)
            case .downloading(let status):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .failed(let message):
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Download failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Retry Download") {
                    Task { await engine.downloadModel() }
                }
                .font(.caption)
            }
        }
    }

    private func hotkeyRow(icon: String, label: String, binding: HotkeyBinding) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .leading)
            Text(binding.displayString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle:
            return .secondary
        case .listening:
            return .green
        case .processing:
            return .orange
        }
    }
}
