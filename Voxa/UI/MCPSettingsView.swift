import SwiftUI

struct MCPSettingsView: View {
    let mcpManager: MCPManager
    @State private var showingAddSheet = false
    @State private var editingServer: MCPServerConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mcpManager.configStore.servers.isEmpty {
                Text("No MCP servers configured.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
            } else {
                ForEach(mcpManager.configStore.servers) { server in
                    MCPServerRow(
                        server: server,
                        connection: mcpManager.connections[server.id],
                        onToggle: { enabled in
                            Task { await mcpManager.toggleServer(id: server.id, enabled: enabled) }
                        },
                        onReconnect: {
                            Task { await mcpManager.reconnect(id: server.id) }
                        },
                        onEdit: {
                            editingServer = server
                        },
                        onRemove: {
                            Task { await mcpManager.removeServer(id: server.id) }
                        }
                    )
                }
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .sheet(isPresented: $showingAddSheet) {
            MCPServerFormSheet(title: "Add MCP Server") { config in
                Task { await mcpManager.addServer(config) }
            }
        }
        .sheet(item: $editingServer) { server in
            MCPServerFormSheet(title: "Edit MCP Server", existing: server) { config in
                Task { await mcpManager.updateServer(config) }
            }
        }
    }
}

// MARK: - Server Row

private struct MCPServerRow: View {
    let server: MCPServerConfig
    let connection: MCPConnection?
    let onToggle: (Bool) -> Void
    let onReconnect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Name
                Text(server.name)
                    .font(.body)
                    .fontWeight(.medium)

                // Transport badge
                Text(server.transport.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                // Status text
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Reconnect
                Button(action: onReconnect) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Reconnect")

                // Edit
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit")

                // Enable toggle
                Toggle("", isOn: Binding(
                    get: { server.enabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                // Remove
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }

            // Connection details
            if server.transport == .stdio, let command = server.command {
                let args = server.args?.joined(separator: " ") ?? ""
                Text("command: \(command) \(args)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if server.transport == .http, let url = server.url {
                Text("url: \(url)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Error message
            if case .error(let msg) = connection?.status {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Discovered tools (expandable)
            if let conn = connection, !conn.discoveredTools.isEmpty {
                DisclosureGroup("Tools (\(conn.discoveredTools.count))", isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(conn.discoveredTools, id: \.name) { tool in
                            HStack(spacing: 4) {
                                Text(tool.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if let desc = tool.description {
                                    Text("— \(desc)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        guard let conn = connection else { return .gray }
        switch conn.status {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        guard let conn = connection else {
            return server.enabled ? "Not started" : "Disabled"
        }
        return conn.status.displayText
    }
}

// MARK: - Add/Edit Form Sheet

private struct MCPServerFormSheet: View {
    let title: String
    var existing: MCPServerConfig?
    let onSave: (MCPServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var transport: MCPTransportType = .stdio
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var envPairs: [(key: String, value: String)] = []
    @State private var url: String = ""

    init(title: String, existing: MCPServerConfig? = nil, onSave: @escaping (MCPServerConfig) -> Void) {
        self.title = title
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("Transport", selection: $transport) {
                    Text("stdio").tag(MCPTransportType.stdio)
                    Text("HTTP").tag(MCPTransportType.http)
                }
                .pickerStyle(.segmented)

                if transport == .stdio {
                    TextField("Command", text: $command)
                        .textFieldStyle(.roundedBorder)
                    TextField("Arguments (space-separated)", text: $args)
                        .textFieldStyle(.roundedBorder)

                    Section("Environment Variables") {
                        ForEach(envPairs.indices, id: \.self) { index in
                            HStack {
                                TextField("Key", text: Binding(
                                    get: { envPairs[index].key },
                                    set: { envPairs[index].key = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                TextField("Value", text: Binding(
                                    get: { envPairs[index].value },
                                    set: { envPairs[index].value = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                Button {
                                    envPairs.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Variable") {
                            envPairs.append((key: "", value: ""))
                        }
                        .font(.caption)
                    }
                } else {
                    TextField("URL", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || (transport == .stdio && command.isEmpty) || (transport == .http && url.isEmpty))
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            if let existing {
                name = existing.name
                transport = existing.transport
                command = existing.command ?? ""
                args = existing.args?.joined(separator: " ") ?? ""
                url = existing.url ?? ""
                if let env = existing.env {
                    envPairs = env.map { (key: $0.key, value: $0.value) }
                }
            }
        }
    }

    private func save() {
        let parsedArgs = args.split(separator: " ").map(String.init)
        var env: [String: String]?
        let validPairs = envPairs.filter { !$0.key.isEmpty }
        if !validPairs.isEmpty {
            env = Dictionary(uniqueKeysWithValues: validPairs.map { ($0.key, $0.value) })
        }

        let config = MCPServerConfig(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            enabled: existing?.enabled ?? true,
            transport: transport,
            command: transport == .stdio ? command : nil,
            args: transport == .stdio ? parsedArgs : nil,
            env: transport == .stdio ? env : nil,
            url: transport == .http ? url : nil
        )
        onSave(config)
    }
}
