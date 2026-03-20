import SwiftUI

/// Settings section for managing sub-agents defined as agents.md files.
struct SubAgentSettingsView: View {
    let subAgentManager: SubAgentManager
    let mcpConfigStore: MCPServerConfigStore
    @State private var editingAgent: SubAgentDefinition?
    @State private var isAddingNew = false
    @State private var agentToDelete: SubAgentDefinition?
    @State private var toolsInspectAgent: SubAgentDefinition?

    private var builtInAgents: [SubAgentDefinition] {
        subAgentManager.builtInDefinitions
    }

    private var customAgents: [SubAgentDefinition] {
        subAgentManager.customDefinitions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // MARK: - Built-in Agents
            sectionHeader("Built-in", icon: "cpu")

            ForEach(builtInAgents) { definition in
                agentRow(definition)
            }

            // MARK: - Custom Agents
            sectionHeader("Custom", icon: "person.crop.rectangle.stack")

            if customAgents.isEmpty {
                Text("No custom agents yet. Click \"Add Agent\" to create one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(customAgents) { definition in
                    agentRow(definition)
                }
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
        .alert("Delete Agent?", isPresented: Binding(
            get: { agentToDelete != nil },
            set: { if !$0 { agentToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let agent = agentToDelete {
                    subAgentManager.delete(agent)
                }
                agentToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                agentToDelete = nil
            }
        } message: {
            Text("This will delete \(agentToDelete?.name ?? "this agent"). This cannot be undone.")
        }
        .sheet(item: $toolsInspectAgent) { agent in
            AgentToolsSheet(agent: agent, mcpConfigStore: mcpConfigStore)
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

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func agentRow(_ definition: SubAgentDefinition) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(definition.name)
                        .font(.system(size: 13, weight: .medium))
                    if definition.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(.secondary)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(definition.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Tools & MCP button — shows tool count badge
            let toolCount = definition.builtinTools.count + definition.mcpServers.count
            if toolCount > 0 {
                Button { toolsInspectAgent = definition } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }

            // Delete button (custom agents only)
            if !definition.isBuiltIn {
                Button {
                    agentToDelete = definition
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
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
        .contextMenu {
            Button {
                toolsInspectAgent = definition
            } label: {
                Label("View Tools", systemImage: "wrench.and.screwdriver")
            }
            Button {
                isAddingNew = false
                editingAgent = definition
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if !definition.isBuiltIn {
                Divider()
                Button(role: .destructive) {
                    agentToDelete = definition
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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
                Text(agent.isBuiltIn ? agent.name : (isNew ? "New Agent" : "Edit Agent"))
                    .font(.headline)
                if agent.isBuiltIn {
                    Text("BUILT-IN")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                if !isNew && !agent.isBuiltIn {
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
                    if agent.isBuiltIn {
                        // Built-in: read-only identity, editable runtime config only
                        builtInInfoSection
                    } else {
                        // Custom: full editor
                        customEditorSection
                    }

                    // Shared: runtime config (always editable)
                    runtimeConfigSection
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button(agent.isBuiltIn ? "Done" : "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if !agent.isBuiltIn {
                    Button(isNew ? "Create" : "Save") {
                        let final = buildPreviewAgent()
                        onSave(final)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(agent.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 520, height: agent.isBuiltIn ? 340 : 620)
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

    // MARK: - Built-in Info (read-only)

    private var builtInInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Read-only identity fields
            readOnlyField("ID", value: agent.id, monospaced: true)
            readOnlyField("Description", value: agent.description)
            readOnlyField("Builtin Tools", value: agent.builtinTools.joined(separator: ", "), monospaced: true)
        }
    }

    private func readOnlyField(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.primary.opacity(0.7))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Custom Editor (full)

    private var customEditorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Name") {
                TextField("Agent name", text: $agent.name)
                    .textFieldStyle(.roundedBorder)
            }

            field("ID") {
                TextField("unique_id", text: $agentId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

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
    }

    // MARK: - Runtime Config (shared)

    private var runtimeConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            mcpServers: agent.isBuiltIn ? [] : Array(selectedMCPIds),
            providerOverride: agent.providerOverride,
            modelOverride: agent.modelOverride,
            timeout: agent.timeout,
            maxToolCalls: agent.maxToolCalls,
            isEnabled: agent.isEnabled,
            isBuiltIn: agent.isBuiltIn,
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

// MARK: - Agent Tools & MCP Inspector Sheet

private struct AgentToolsSheet: View {
    let agent: SubAgentDefinition
    let mcpConfigStore: MCPServerConfigStore
    @Environment(\.dismiss) private var dismiss

    /// Resolved builtin tool instances for display.
    private var builtinTools: [(name: String, tool: any AgentTool)] {
        agent.builtinTools.compactMap { name in
            guard let tool = ToolRegistry.builtinTool(named: name) else { return nil }
            return (name: name, tool: tool)
        }
    }

    /// Tools grouped by category. Each entry is (category, icon, resolved tools).
    /// Tools not in any category are collected under "Other".
    private var categorizedTools: [(category: String, icon: String, tools: [(name: String, tool: any AgentTool)])] {
        guard !agent.toolCategories.isEmpty else { return [] }

        var result: [(category: String, icon: String, tools: [(name: String, tool: any AgentTool)])] = []
        var categorizedNames = Set<String>()

        for cat in agent.toolCategories {
            let resolved: [(name: String, tool: any AgentTool)] = cat.tools.compactMap { name in
                guard let tool = ToolRegistry.builtinTool(named: name) else { return nil }
                return (name: name, tool: tool)
            }
            if !resolved.isEmpty {
                result.append((category: cat.name, icon: cat.icon, tools: resolved))
                categorizedNames.formUnion(cat.tools)
            }
        }

        // Collect uncategorized tools
        let uncategorized = agent.builtinTools.filter { !categorizedNames.contains($0) }.compactMap { name in
            guard let tool = ToolRegistry.builtinTool(named: name) else { return nil as (name: String, tool: any AgentTool)? }
            return (name: name, tool: tool)
        }
        if !uncategorized.isEmpty {
            result.append((category: "Other", icon: "wrench", tools: uncategorized))
        }

        return result
    }

    /// Resolved MCP server configs for this agent.
    private var mcpServers: [MCPServerConfig] {
        agent.mcpServers.compactMap { mcpConfigStore.server(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    Text("Tools & MCP Servers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Builtin Tools — categorized or flat
                    if !agent.toolCategories.isEmpty {
                        // Categorized display
                        ForEach(categorizedTools, id: \.category) { group in
                            toolsSectionHeader(
                                group.category,
                                icon: group.icon,
                                count: group.tools.count,
                                color: .blue
                            )

                            VStack(spacing: 1) {
                                ForEach(group.tools, id: \.name) { entry in
                                    builtinToolRow(entry.tool)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else if !builtinTools.isEmpty {
                        // Flat display (no categories defined)
                        toolsSectionHeader(
                            "Builtin Tools",
                            icon: "hammer.fill",
                            count: builtinTools.count,
                            color: .blue
                        )

                        VStack(spacing: 1) {
                            ForEach(builtinTools, id: \.name) { entry in
                                builtinToolRow(entry.tool)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // MCP Servers
                    if !agent.mcpServers.isEmpty {
                        toolsSectionHeader(
                            "MCP Servers",
                            icon: "server.rack",
                            count: mcpServers.count,
                            color: .purple
                        )

                        if mcpServers.isEmpty {
                            Text("Configured MCP servers not found in config store.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        } else {
                            VStack(spacing: 1) {
                                ForEach(mcpServers) { server in
                                    mcpServerRow(server)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if builtinTools.isEmpty && agent.mcpServers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 28))
                                .foregroundStyle(.quaternary)
                            Text("No tools configured")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Add builtin tools or MCP servers to give this agent capabilities.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
    }

    // MARK: - Section Header

    private func toolsSectionHeader(_ title: String, icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(color)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Builtin Tool Row

    private func builtinToolRow(_ tool: any AgentTool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tool.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                if tool.requiresConfirmation {
                    Text("CONFIRM")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Text("\(tool.parameters.count) param\(tool.parameters.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(tool.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Parameters
            if !tool.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(tool.parameters, id: \.name) { param in
                        HStack(alignment: .top, spacing: 6) {
                            HStack(spacing: 3) {
                                Text(param.name)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                Text(param.type)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minWidth: 100, alignment: .leading)

                            if param.required {
                                Text("*")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.6))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(param.description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)

                                if let enumValues = param.enumValues, !enumValues.isEmpty {
                                    HStack(spacing: 3) {
                                        ForEach(enumValues, id: \.self) { value in
                                            Text(value)
                                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .foregroundStyle(.blue.opacity(0.8))
                                                .background(Color.blue.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - MCP Server Row

    private func mcpServerRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.enabled ? .green : .gray)
                .frame(width: 7, height: 7)

            Text(server.name)
                .font(.system(size: 12, weight: .medium))

            Text(server.transport.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            Spacer()

            if !server.enabled {
                Text("DISABLED")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
    }
}
