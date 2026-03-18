import SwiftUI
import Carbon

/// A button that, when clicked, captures the next key combination via the existing
/// HotkeyManager event tap and records it as a HotkeyBinding.
struct HotkeyRecorderView: View {
    let hotkeyManager: HotkeyManager
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "Press keys..." : binding.displayString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isRecording ? .orange : .primary)
                .frame(minWidth: 130, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.orange.opacity(0.1) : Color(.controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.orange : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }

            if isRecording {
                Button("Cancel") {
                    stopRecording()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        hotkeyManager.recordingCallback = { [self] keyCode, flags in
            binding = HotkeyBinding(keyCode: keyCode, modifiers: flags)
            isRecording = false
        }
    }

    private func stopRecording() {
        hotkeyManager.recordingCallback = nil
        isRecording = false
    }
}
