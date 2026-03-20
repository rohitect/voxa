import SwiftUI

/// A sheet that displays the full processing trace for an assistant message.
/// Supports both a static trace (completed messages) and a live-updating trace
/// via an observable `AgentPanelState`.
struct TraceInspectorView: View {
    /// Static trace for completed messages.
    let trace: MessageTrace?
    /// Optional live panel state — when provided, the view observes `liveTrace` for real-time updates.
    var panelState: AgentPanelState?
    /// Called to dismiss this view (used by the overlay host).
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// The trace to display: live trace takes priority, falls back to static.
    private var displayTrace: MessageTrace? {
        panelState?.liveTrace ?? trace
    }

    private func close() {
        onDismiss?()
        dismiss()
    }

    init(trace: MessageTrace, onDismiss: (() -> Void)? = nil) {
        self.trace = trace
        self.panelState = nil
        self.onDismiss = onDismiss
    }

    init(panelState: AgentPanelState, onDismiss: (() -> Void)? = nil) {
        self.trace = nil
        self.panelState = panelState
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            if let displayTrace {
                header(for: displayTrace)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(displayTrace.entries.enumerated()), id: \.element.id) { index, entry in
                                TraceEntryRow(entry: entry, isLast: index == displayTrace.entries.count - 1)
                            }
                            Color.clear.frame(height: 1).id("traceBottom")
                        }
                        .padding(16)
                    }
                    .onChange(of: displayTrace.entries.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("traceBottom", anchor: .bottom)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for trace data...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture {} // keep taps inside from propagating
        .onExitCommand { close() }
    }

    // MARK: - Header

    private func header(for trace: MessageTrace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Trace Inspector")
                        .font(.headline)
                    if trace.completedAt == nil {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Label(trace.agentName, systemImage: "person.crop.circle")
                    Label(trace.provider, systemImage: "cpu")
                    Label(trace.model, systemImage: "brain")
                    if let ms = trace.durationMs {
                        Label(formatDuration(ms), systemImage: "clock")
                    } else {
                        Label(formatDuration(Int(Date().timeIntervalSince(trace.startedAt) * 1000)), systemImage: "clock")
                    }
                    if let usage = trace.totalUsage {
                        Label("\(usage.totalTokens) tokens", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button { close() } label: {
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
            // Timeline dot (no connector line — avoids layout overflow in nested contexts)
            Circle()
                .fill(iconColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

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
        case .subAgentDelegation(let name, _, _, let ms, _):
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

        case .subAgentDelegation(let agentName, let input, let output, _, let steps):
            VStack(alignment: .leading, spacing: 6) {
                traceCodeBlock("Task", input)

                // Render nested sub-agent trace steps
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Internal Steps (\(agentName))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                TraceEntryRow(entry: step, isLast: index == steps.count - 1)
                            }
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                traceCodeBlock("Final Output", output)
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
            ScrollView {
                Text(displayText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 48, maxHeight: 200)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func formatJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" || trimmed == "{ }" {
            return "(no arguments)"
        }
        guard let data = trimmed.data(using: .utf8),
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
