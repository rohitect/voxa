import SwiftUI

/// A sheet that displays the full processing trace for an assistant message.
struct TraceInspectorView: View {
    let trace: MessageTrace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trace.entries.enumerated()), id: \.element.id) { index, entry in
                        TraceEntryRow(entry: entry, isLast: index == trace.entries.count - 1)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 400, idealHeight: 560)
        .background(WindowAccessor())
        .background(Color.clear)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Trace Inspector")
                    .font(.headline)
                HStack(spacing: 8) {
                    Label(trace.agentName, systemImage: "person.crop.circle")
                    Label(trace.provider, systemImage: "cpu")
                    Label(trace.model, systemImage: "brain")
                    if let ms = trace.durationMs {
                        Label(formatDuration(ms), systemImage: "clock")
                    }
                    if let usage = trace.totalUsage {
                        Label("\(usage.totalTokens) tokens", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

// MARK: - Trace Entry Row

private struct TraceEntryRow: View {
    let entry: TraceEntry
    let isLast: Bool
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(iconColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 11))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }

                if hasExpandableContent {
                    expandableContent
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }

    // MARK: - Entry-specific rendering

    private var iconName: String {
        switch entry.kind {
        case .llmRequest: return "arrow.up.circle"
        case .llmResponse: return "arrow.down.circle"
        case .toolExecution: return "wrench"
        case .subAgentDelegation: return "person.2"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .llmRequest: return .blue
        case .llmResponse: return .green
        case .toolExecution(let summary):
            return summary.isError ? .red : .orange
        case .subAgentDelegation: return .purple
        case .error: return .red
        }
    }

    private var title: String {
        switch entry.kind {
        case .llmRequest(let msgCount, let toolCount, let iteration):
            return "LLM Request (iter \(iteration)) — \(msgCount) messages, \(toolCount) tools"
        case .llmResponse(_, let toolCalls):
            if let calls = toolCalls, !calls.isEmpty {
                let names = calls.map(\.name).joined(separator: ", ")
                return "LLM Response — requested: \(names)"
            }
            return "LLM Response — final text"
        case .toolExecution(let summary):
            let badge = summary.isMCP ? " [MCP]" : ""
            let status = summary.isError ? " (error)" : ""
            let duration = summary.durationMs.map { " (\(formatMs($0)))" } ?? ""
            return "\(summary.name)\(badge)\(status)\(duration)"
        case .subAgentDelegation(let name, _, _, let ms):
            return "Sub-agent: \(name) (\(formatMs(ms)))"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.timestamp)
    }

    private var hasExpandableContent: Bool {
        switch entry.kind {
        case .llmResponse(let content, _):
            return content != nil && !(content?.isEmpty ?? true)
        case .toolExecution:
            return true
        case .subAgentDelegation:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var expandableContent: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                Text(isExpanded ? "Collapse" : "Expand")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)

        if isExpanded {
            expandedDetail
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        switch entry.kind {
        case .llmResponse(let content, _):
            if let content, !content.isEmpty {
                traceCodeBlock("Response", content)
            }

        case .toolExecution(let summary):
            VStack(alignment: .leading, spacing: 6) {
                traceCodeBlock("Arguments", formatJSON(summary.arguments))
                if let output = summary.output {
                    traceCodeBlock(summary.isError ? "Error Output" : "Output", output)
                }
            }

        case .subAgentDelegation(_, let input, let output, _):
            VStack(alignment: .leading, spacing: 6) {
                traceCodeBlock("Input", input)
                traceCodeBlock("Output", output)
            }

        default:
            EmptyView()
        }
    }

    private func traceCodeBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            let displayText = text.count > 2000 ? String(text.prefix(2000)) + "\n\n[Truncated — \(text.count) chars total]" : text
            Text(displayText)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func formatJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return str
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }
}
