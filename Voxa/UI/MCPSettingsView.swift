import SwiftUI

struct MCPSettingsView: View {
    let mcpManager: MCPManager
    @State private var showingAddSheet = false
    @State private var showingRepoSheet = false
    @State private var showingLocalSheet = false
    @State private var editingServer: MCPServerConfig?
    @State private var buildingServer: MCPServerConfig?

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
                        onUpdate: server.isRepoManaged ? { () -> Void in
                            Task { try? await mcpManager.updateFromRepo(id: server.id) }
                        } : nil,
                        onRebuild: (server.buildCommand != nil && !server.buildCommand!.isEmpty) ? { () -> Void in
                            buildingServer = server
                        } : nil,
                        onEdit: {
                            editingServer = server
                        },
                        onRemove: {
                            Task {
                                if server.isVoxaManaged {
                                    await mcpManager.removeServerAndRepo(id: server.id)
                                } else {
                                    await mcpManager.removeServer(id: server.id)
                                }
                            }
                        }
                    )
                }
            }

            HStack(spacing: 8) {
                Button {
                    showingRepoSheet = true
                } label: {
                    Label("From Repository", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingLocalSheet = true
                } label: {
                    Label("From Local Path", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Manual", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            MCPServerFormSheet(title: "Add MCP Server") { config in
                Task { await mcpManager.addServer(config) }
            }
        }
        .sheet(isPresented: $showingRepoSheet) {
            MCPRepoInstallSheet(mcpManager: mcpManager)
        }
        .sheet(isPresented: $showingLocalSheet) {
            MCPLocalInstallSheet(mcpManager: mcpManager)
        }
        .sheet(item: $editingServer) { server in
            MCPServerFormSheet(title: "Edit MCP Server", existing: server) { config in
                Task { await mcpManager.updateServer(config) }
            }
        }
        .sheet(item: $buildingServer) { server in
            MCPBuildSheet(server: server, mcpManager: mcpManager)
        }
    }
}

// MARK: - Server Row

private struct MCPServerRow: View {
    let server: MCPServerConfig
    let connection: MCPConnection?
    let onToggle: (Bool) -> Void
    let onReconnect: () -> Void
    let onUpdate: (() -> Void)?
    let onRebuild: (() -> Void)?
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

                // Source badge
                if server.isRepoManaged {
                    Text("REPO")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                } else if server.isLocalManaged {
                    Text("LOCAL")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Status text
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Update (repo-managed only)
                if let onUpdate {
                    Button(action: onUpdate) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Update from repository")
                }

                // Rebuild
                if let onRebuild {
                    Button(action: onRebuild) {
                        Image(systemName: "hammer")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Rebuild")
                }

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

            // Build command
            if let build = server.buildCommand, !build.isEmpty {
                Text("build: \(build)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Execute command
            if server.transport == .stdio, let command = server.command {
                let args = server.args?.joined(separator: " ") ?? ""
                Text("run: \(command) \(args)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if server.transport == .http, let url = server.url {
                Text("url: \(url)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Source info
            if let repo = server.repository {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text(repo)
                        .lineLimit(1)
                    if let fetched = server.lastFetched {
                        Text("  Fetched \(fetched, style: .relative) ago")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let localPath = server.localSource {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text("Copied from \(localPath)")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
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

// MARK: - Repository Install Sheet

private struct MCPRepoInstallSheet: View {
    let mcpManager: MCPManager
    @Environment(\.dismiss) private var dismiss

    @State private var repoURL: String = ""
    @State private var name: String = ""
    @State private var buildCommand: String = ""
    @State private var transport: MCPTransportType = .stdio
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var url: String = ""
    @State private var envPairs: [(key: String, value: String)] = []
    @State private var isInstalling = false
    @State private var installOutput: String = ""
    @State private var installError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Install MCP from Repository")
                .font(.headline)

            Form {
                TextField("Git Repository URL", text: $repoURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isInstalling)

                TextField("Server Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isInstalling)

                Section("Build") {
                    TextField("Build Command (e.g. npm install && npm run build)", text: $buildCommand)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isInstalling)

                    Text("Leave empty to auto-detect from project type. Use **{MCP_ROOT}** for the install path.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Execute") {
                    Picker("Transport", selection: $transport) {
                        Text("stdio").tag(MCPTransportType.stdio)
                        Text("HTTP").tag(MCPTransportType.http)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isInstalling)

                    if transport == .stdio {
                        TextField("Command (e.g. node, python3)", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)
                        TextField("Arguments (space-separated)", text: $args)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)

                        Text("Leave empty to auto-detect. Use **{MCP_ROOT}** for the install path.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        TextField("URL (e.g. http://localhost:3000/mcp)", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)
                    }
                }

                Section("Environment Variables (optional)") {
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
                    .disabled(isInstalling)
                }
            }
            .formStyle(.grouped)

            // Install progress / output
            if isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cloning and building...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !installOutput.isEmpty {
                ScrollView {
                    Text(installOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInstalling)
                Spacer()

                Text("Clones to ~/.voxa/mcp-repos/")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()
                Button("Install") {
                    performInstall()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repoURL.isEmpty || name.isEmpty || isInstalling)
            }
        }
        .padding()
        .frame(width: 500, height: 560)
    }

    private func performInstall() {
        isInstalling = true
        installError = nil
        installOutput = ""

        var env: [String: String]?
        let validPairs = envPairs.filter { !$0.key.isEmpty }
        if !validPairs.isEmpty {
            env = Dictionary(uniqueKeysWithValues: validPairs.map { ($0.key, $0.value) })
        }

        let trimmedBuild = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedArgs = trimmedArgs.isEmpty ? nil : trimmedArgs.split(separator: " ").map(String.init)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let result = try await mcpManager.installFromRepo(
                    repository: repoURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    buildCommand: trimmedBuild.isEmpty ? nil : trimmedBuild,
                    command: trimmedCommand.isEmpty ? nil : trimmedCommand,
                    args: parsedArgs,
                    transport: transport,
                    url: transport == .http ? trimmedURL : nil,
                    env: env
                )
                await MainActor.run {
                    installOutput = result.output
                    isInstalling = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
}

// MARK: - Local Path Install Sheet

private struct MCPLocalInstallSheet: View {
    let mcpManager: MCPManager
    @Environment(\.dismiss) private var dismiss

    @State private var localPath: String = ""
    @State private var name: String = ""
    @State private var buildCommand: String = ""
    @State private var transport: MCPTransportType = .stdio
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var url: String = ""
    @State private var envPairs: [(key: String, value: String)] = []
    @State private var isInstalling = false
    @State private var installOutput: String = ""
    @State private var installError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Install MCP from Local Path")
                .font(.headline)

            Form {
                HStack {
                    TextField("Folder Path", text: $localPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isInstalling)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            localPath = url.path
                            if name.isEmpty {
                                name = url.lastPathComponent
                            }
                        }
                    }
                    .disabled(isInstalling)
                }

                TextField("Server Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isInstalling)

                Section("Build") {
                    TextField("Build Command (e.g. npm install && npm run build)", text: $buildCommand)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isInstalling)

                    Text("Leave empty to auto-detect from project type. Use **{MCP_ROOT}** for the install path.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Execute") {
                    Picker("Transport", selection: $transport) {
                        Text("stdio").tag(MCPTransportType.stdio)
                        Text("HTTP").tag(MCPTransportType.http)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isInstalling)

                    if transport == .stdio {
                        TextField("Command (e.g. node, python3)", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)
                        TextField("Arguments (space-separated)", text: $args)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)

                        Text("Leave empty to auto-detect. Use **{MCP_ROOT}** for the install path.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        TextField("URL (e.g. http://localhost:3000/mcp)", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isInstalling)
                    }
                }

                Section("Environment Variables (optional)") {
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
                    .disabled(isInstalling)
                }
            }
            .formStyle(.grouped)

            if isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Copying and building...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !installOutput.isEmpty {
                ScrollView {
                    Text(installOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInstalling)
                Spacer()

                Text("Folder will be copied to ~/.voxa/mcp-repos/")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()
                Button("Install") {
                    performInstall()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localPath.isEmpty || name.isEmpty || isInstalling)
            }
        }
        .padding()
        .frame(width: 500, height: 560)
    }

    private func performInstall() {
        isInstalling = true
        installError = nil
        installOutput = ""

        var env: [String: String]?
        let validPairs = envPairs.filter { !$0.key.isEmpty }
        if !validPairs.isEmpty {
            env = Dictionary(uniqueKeysWithValues: validPairs.map { ($0.key, $0.value) })
        }

        let trimmedBuild = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedArgs = trimmedArgs.isEmpty ? nil : trimmedArgs.split(separator: " ").map(String.init)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let result = try await mcpManager.installFromLocal(
                    path: localPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    buildCommand: trimmedBuild.isEmpty ? nil : trimmedBuild,
                    command: trimmedCommand.isEmpty ? nil : trimmedCommand,
                    args: parsedArgs,
                    transport: transport,
                    url: transport == .http ? trimmedURL : nil,
                    env: env
                )
                await MainActor.run {
                    installOutput = result.output
                    isInstalling = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
}

// MARK: - Add/Edit Form Sheet (Manual)

private struct MCPServerFormSheet: View {
    let title: String
    var existing: MCPServerConfig?
    let onSave: (MCPServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var buildCommand: String = ""
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

                Section("Build (optional)") {
                    TextField("Build Command (e.g. npm install && npm run build)", text: $buildCommand)
                        .textFieldStyle(.roundedBorder)

                    Text("Use **{MCP_ROOT}** in command or arguments to reference the MCP server's root path.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Execute") {
                    Picker("Transport", selection: $transport) {
                        Text("stdio").tag(MCPTransportType.stdio)
                        Text("HTTP").tag(MCPTransportType.http)
                    }
                    .pickerStyle(.segmented)

                    if transport == .stdio {
                        TextField("Command (e.g. npx, node, python3)", text: $command)
                            .textFieldStyle(.roundedBorder)
                        TextField("Arguments (space-separated)", text: $args)
                            .textFieldStyle(.roundedBorder)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("For npx packages: command = **npx**, args = **-y package-name@latest**")
                            Text("Use **{MCP_ROOT}** to reference the MCP server's root path.")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    } else {
                        TextField("URL", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }
                }

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
        .frame(width: 460)
        .onAppear {
            if let existing {
                name = existing.name
                buildCommand = existing.buildCommand ?? ""
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

        let trimmedBuild = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = MCPServerConfig(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            enabled: existing?.enabled ?? true,
            transport: transport,
            buildCommand: trimmedBuild.isEmpty ? nil : trimmedBuild,
            command: transport == .stdio ? command : nil,
            args: transport == .stdio ? parsedArgs : nil,
            env: env,
            url: transport == .http ? url : nil,
            repository: existing?.repository,
            localSource: existing?.localSource,
            lastFetched: existing?.lastFetched
        )
        onSave(config)
    }
}

// MARK: - Build Sheet

private struct MCPBuildSheet: View {
    let server: MCPServerConfig
    let mcpManager: MCPManager
    @Environment(\.dismiss) private var dismiss

    @State private var output: String = ""
    @State private var isRunning = false
    @State private var exitCode: Int32?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "hammer")
                Text("Build — \(server.name)")
                    .font(.headline)
            }

            // Show the resolved build command
            if let build = server.buildCommand {
                let resolved = resolvedBuildCommand(build)
                HStack(spacing: 4) {
                    Text("$")
                        .foregroundStyle(.green)
                    Text(resolved)
                        .lineLimit(2)
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Output terminal
            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? " " : output)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("bottom")
                }
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxHeight: .infinity)
                .onChange(of: output) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            // Status + buttons
            HStack {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let code = exitCode {
                    Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(code == 0 ? .green : .red)
                    Text(code == 0 ? "Build succeeded" : "Build failed (exit \(code))")
                        .font(.caption)
                        .foregroundStyle(code == 0 ? .green : .red)
                }

                Spacer()

                if !isRunning {
                    Button("Close") {
                        // Reconnect the server after build
                        if exitCode == 0 {
                            Task { await mcpManager.reconnect(id: server.id) }
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding()
        .frame(width: 520, height: 380)
        .onAppear {
            runBuild()
        }
    }

    private func resolvedBuildCommand(_ build: String) -> String {
        let mcpRoot = server.managedDirectory?.path ?? "<MCP_ROOT>"
        return build.replacingOccurrences(of: "{MCP_ROOT}", with: mcpRoot)
    }

    private func runBuild() {
        guard let build = server.buildCommand, !build.isEmpty else { return }
        guard let dir = server.managedDirectory else {
            output = "Error: No managed directory for this server.\n"
            exitCode = 1
            return
        }

        let resolved = build.replacingOccurrences(of: "{MCP_ROOT}", with: dir.path)
        let fullCommand = "cd '\(dir.path.replacingOccurrences(of: "'", with: "'\\''"))' && \(resolved)"

        isRunning = true
        output = ""

        // Disconnect before building
        Task {
            if let connection = mcpManager.connections[server.id] {
                await connection.disconnect()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", fullCommand]

            var env = ProcessInfo.processInfo.environment
            if let path = env["PATH"] {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
            }
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        output += str
                    }
                }
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    output += "Failed to start: \(error.localizedDescription)\n"
                    isRunning = false
                    exitCode = 1
                }
                return
            }

            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil

            // Read any remaining data
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: remaining, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    output += str
                }
            }

            let code = process.terminationStatus
            DispatchQueue.main.async {
                isRunning = false
                exitCode = code
            }
        }
    }
}
