import SwiftUI

/// Settings section for managing sub-agents.
struct SubAgentSettingsView: View {
    let subAgentManager: SubAgentManager

    var body: some View {
        ForEach(subAgentManager.sortedDefinitions) { definition in
            SettingsRow(label: definition.name) {
                HStack(spacing: 6) {
                    // Tool count badge
                    Text("\(definition.allowedTools.count) tools")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())

                    // Provider override indicator
                    if definition.providerOverride != nil {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help("Uses provider: \(definition.providerOverride!)")
                    }

                    // Custom badge
                    if isCustom(definition.id) {
                        Text("Custom")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    Toggle("", isOn: Binding(
                        get: { subAgentManager.isEnabled(definition.id) },
                        set: { subAgentManager.setEnabled(definition.id, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }

        // Info row
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Add JSON files to ~/.voxa/agent/subagents/ for custom agents.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reload") {
                subAgentManager.reloadCustom()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func isCustom(_ id: String) -> Bool {
        if case .custom = subAgentManager.sources[id] {
            return true
        }
        return false
    }
}
