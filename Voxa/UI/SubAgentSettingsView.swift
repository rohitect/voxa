import SwiftUI

/// Settings section for managing sub-agents defined as agents.md files.
struct SubAgentSettingsView: View {
    let subAgentManager: SubAgentManager
    let mcpConfigStore: MCPServerConfigStore
    @State private var editingAgent: SubAgentDefinition?
    @State private var isAddingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(subAgentManager.sortedDefinitions) { definition in
                agentRow(definition)
            }

            // Actions row
            HStack {
                Button {
                    isAddingNew = true
                    editingAgent = SubAgentDefinition(
                        id: "new_agent",
                        name: "New Agent",
                        description: "Describe what this agent does.",
                        systemPrompt: "You are a helpful agent."
                    )
                } label: {
                    Label("Add Agent", systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    subAgentManager.reload()
                } label: {
                    Label("Reload from Disk", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Info
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text("Agents are stored as markdown files in ~/.voxa/agent/agents/")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .sheet(item: $editingAgent) { agent in
            AgentEditorSheet(
                agent: agent,
                originalId: agent.id,
                isNew: isAddingNew,
                mcpServers: mcpConfigStore.servers,
                onSave: { updated in
                    // If ID changed, delete the old file
                    if !isAddingNew && updated.id != agent.id {
                        subAgentManager.delete(agent)
                    }
                    subAgentManager.save(updated)
                    editingAgent = nil
                    isAddingNew = false
                },
                onDelete: {
                    subAgentManager.delete(agent)
                    editingAgent = nil
                    isAddingNew = false
                },
                onCancel: {
                    editingAgent = nil
                    isAddingNew = false
                }
            )
        }
    }

    private func agentRow(_ definition: SubAgentDefinition) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .font(.system(size: 13, weight: .medium))
                Text(definition.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // MCP server count badge
            if !definition.mcpServers.isEmpty {
                Text("\(definition.mcpServers.count) MCP\(definition.mcpServers.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Edit button
            Button {
                isAddingNew = false
                editingAgent = definition
            } label: {
                Text("Edit")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { subAgentManager.isEnabled(definition.id) },
                set: { subAgentManager.setEnabled(definition.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
    }
}

// MARK: - Agent Editor Sheet

private struct AgentEditorSheet: View {
    @State var agent: SubAgentDefinition
    let originalId: String
    let isNew: Bool
    let mcpServers: [MCPServerConfig]
    let onSave: (SubAgentDefinition) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var agentId: String = ""
    @State private var selectedMCPIds: Set<String> = []
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Agent" : "Edit Agent")
                    .font(.headline)
                Spacer()
                if !isNew {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .font(.caption)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    field("Name") {
                        TextField("Agent name", text: $agent.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // ID
                    field("ID") {
                        TextField("unique_id", text: $agentId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    // Description
                    field("Description") {
                        TextField("What this agent does", text: $agent.description)
                            .textFieldStyle(.roundedBorder)
                    }

                    // MCP Servers
                    field("MCP Servers") {
                        if mcpServers.isEmpty {
                            Text("No MCP servers configured. Add servers in the MCP settings section.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(mcpServers) { server in
                                    HStack(spacing: 8) {
                                        Toggle("", isOn: Binding(
                                            get: { selectedMCPIds.contains(server.id) },
                                            set: { isOn in
                                                if isOn {
                                                    selectedMCPIds.insert(server.id)
                                                } else {
                                                    selectedMCPIds.remove(server.id)
                                                }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)

                                        Text(server.name)
                                            .font(.system(size: 12))

                                        Text(server.transport.rawValue.uppercased())
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(Capsule())

                                        Spacer()
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text("Each agent gets its own isolated MCP connections.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, -12)

                    // Timeout & Max tool calls
                    HStack(spacing: 16) {
                        field("Timeout (s)") {
                            TextField("60", value: Binding(
                                get: { Int(agent.timeout) },
                                set: { agent.timeout = TimeInterval($0) }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        }

                        field("Max tool calls") {
                            TextField("5", value: $agent.maxToolCalls, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    // Provider / Model overrides
                    HStack(spacing: 16) {
                        field("Provider override") {
                            TextField("(default)", text: Binding(
                                get: { agent.providerOverride ?? "" },
                                set: { agent.providerOverride = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        field("Model override") {
                            TextField("(default)", text: Binding(
                                get: { agent.modelOverride ?? "" },
                                set: { agent.modelOverride = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    // System Prompt / Instructions
                    field("Instructions (System Prompt)") {
                        TextEditor(text: $agent.systemPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 120)
                            .border(Color.secondary.opacity(0.2))
                    }

                    // Raw markdown preview
                    DisclosureGroup("agents.md Preview") {
                        Text(buildPreviewAgent().toMarkdown())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    let final = buildPreviewAgent()
                    onSave(final)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(agent.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 620)
        .onAppear {
            agentId = agent.id
            selectedMCPIds = Set(agent.mcpServers)
        }
        .alert("Delete Agent?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(agent.id).md. This cannot be undone.")
        }
    }

    private func buildPreviewAgent() -> SubAgentDefinition {
        let id = agentId.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "_")

        // If ID changed, clear filePath so save() creates a new file with the new name
        let filePath = (id == originalId) ? agent.filePath : nil

        return SubAgentDefinition(
            id: id,
            name: agent.name,
            description: agent.description,
            systemPrompt: agent.systemPrompt,
            mcpServers: Array(selectedMCPIds),
            providerOverride: agent.providerOverride,
            modelOverride: agent.modelOverride,
            timeout: agent.timeout,
            maxToolCalls: agent.maxToolCalls,
            isEnabled: agent.isEnabled,
            filePath: filePath
        )
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
