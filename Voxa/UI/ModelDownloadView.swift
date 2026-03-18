import SwiftUI

struct ModelDownloadView: View {
    let modelManager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch modelManager.modelState {
            case .notDownloaded:
                Label("No model downloaded", systemImage: "arrow.down.circle")
                    .font(.caption)
                Button("Download \(modelManager.selectedModel)") {
                    Task {
                        await modelManager.downloadSelectedModel()
                    }
                }
                .font(.caption)

            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }

            case .ready:
                Label("Model ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Retry") {
                    Task {
                        await modelManager.downloadSelectedModel()
                    }
                }
                .font(.caption)
            }
        }
    }
}
