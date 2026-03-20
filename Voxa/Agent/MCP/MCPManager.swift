import Foundation
import MCP

/// Lifecycle manager for all MCP server connections.
/// Owns connections, persists config, and registers/unregisters tools in ToolRegistry.
@Observable
final class MCPManager {
    let configStore: MCPServerConfigStore

    private(set) var connections: [String: MCPConnection] = [:]
    private weak var toolRegistry: ToolRegistry?

    /// Which MCP server IDs are assigned to the main agent.
    /// `nil` means "all enabled servers" (backward compatible default).
    var mainAgentMCPServerIDs: [String]? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "agent.main.mcpServers"),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return ids
        }
        set {
            if let ids = newValue {
                if let data = try? JSONEncoder().encode(ids) {
                    UserDefaults.standard.set(data, forKey: "agent.main.mcpServers")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "agent.main.mcpServers")
            }
        }
    }

    init(toolRegistry: ToolRegistry) {
        self.toolRegistry = toolRegistry
        self.configStore = MCPServerConfigStore()
    }

    // MARK: - Lifecycle

    func connectAll() async {
        let assignedIDs = mainAgentMCPServerIDs
        for config in configStore.servers where config.enabled {
            // If main agent has specific MCP assignments, only connect those
            if let assignedIDs, !assignedIDs.contains(config.id) {
                continue
            }
            await connectServer(config)
        }
    }

    func disconnectAll() async {
        for (_, connection) in connections {
            await connection.disconnect()
        }
        connections.removeAll()
    }

    // MARK: - CRUD

    func addServer(_ config: MCPServerConfig) async {
        configStore.add(config)
        if config.enabled {
            await connectServer(config)
        }
    }

    func removeServer(id: String) async {
        if let connection = connections[id] {
            unregisterTools(for: connection)
            await connection.disconnect()
            connections.removeValue(forKey: id)
        }
        configStore.remove(id: id)
    }

    func updateServer(_ config: MCPServerConfig) async {
        // Disconnect old
        if let connection = connections[config.id] {
            unregisterTools(for: connection)
            await connection.disconnect()
            connections.removeValue(forKey: config.id)
        }
        configStore.update(config)

        // Reconnect if enabled
        if config.enabled {
            await connectServer(config)
        }
    }

    func toggleServer(id: String, enabled: Bool) async {
        guard var config = configStore.server(id: id) else { return }
        config.enabled = enabled
        configStore.update(config)

        if enabled {
            await connectServer(config)
        } else {
            if let connection = connections[id] {
                unregisterTools(for: connection)
                await connection.disconnect()
                connections.removeValue(forKey: id)
            }
        }
    }

    func reconnect(id: String) async {
        guard let config = configStore.server(id: id) else { return }
        if let connection = connections[id] {
            unregisterTools(for: connection)
            await connection.disconnect()
            connections.removeValue(forKey: id)
        }
        if config.enabled {
            await connectServer(config)
        }
    }

    /// All discovered tools across all connected servers.
    var allDiscoveredTools: [(serverName: String, tools: [MCP.Tool])] {
        connections.compactMap { (id, conn) in
            guard conn.status.isConnected else { return nil }
            return (serverName: conn.config.name, tools: conn.discoveredTools)
        }
    }

    // MARK: - Repository Management

    /// Install an MCP server from a git repository.
    func installFromRepo(repository: String, name: String,
                         buildCommand: String? = nil,
                         command: String? = nil, args: [String]? = nil,
                         transport: MCPTransportType = .stdio, url: String? = nil,
                         env: [String: String]? = nil) async throws -> MCPInstallResult {
        let result = try await MCPInstaller.install(
            repository: repository, name: name,
            buildCommand: buildCommand,
            command: command, args: args,
            transport: transport, url: url,
            env: env
        )
        configStore.add(result.config)
        if result.config.enabled {
            await connectServer(result.config)
        }
        return result
    }

    /// Install an MCP server from a local folder (copied, no git, no updates).
    func installFromLocal(path: String, name: String,
                          buildCommand: String? = nil,
                          command: String? = nil, args: [String]? = nil,
                          transport: MCPTransportType = .stdio, url: String? = nil,
                          env: [String: String]? = nil) async throws -> MCPInstallResult {
        let result = try await MCPInstaller.installFromLocal(
            path: path, name: name,
            buildCommand: buildCommand,
            command: command, args: args,
            transport: transport, url: url,
            env: env
        )
        configStore.add(result.config)
        if result.config.enabled {
            await connectServer(result.config)
        }
        return result
    }

    /// Pull latest changes and rebuild a repo-managed MCP server.
    func updateFromRepo(id: String) async throws -> MCPInstallResult {
        guard let config = configStore.server(id: id) else {
            throw MCPInstallerError.repoNotFound
        }

        // Disconnect while updating
        if let connection = connections[id] {
            unregisterTools(for: connection)
            await connection.disconnect()
            connections.removeValue(forKey: id)
        }

        let result = try await MCPInstaller.update(config)
        configStore.update(result.config)

        // Reconnect
        if result.config.enabled {
            await connectServer(result.config)
        }

        return result
    }

    /// Re-run the build command for a managed MCP server, then reconnect.
    func rebuild(id: String) async throws -> String {
        guard let config = configStore.server(id: id) else {
            throw MCPInstallerError.repoNotFound
        }

        // Disconnect while rebuilding
        if let connection = connections[id] {
            unregisterTools(for: connection)
            await connection.disconnect()
            connections.removeValue(forKey: id)
        }

        let output = try await MCPInstaller.rebuild(config)

        // Reconnect
        if config.enabled {
            await connectServer(config)
        }

        return output
    }

    /// Remove a Voxa-managed MCP server, including its cloned/copied files.
    func removeServerAndRepo(id: String) async {
        if let config = configStore.server(id: id), config.isVoxaManaged {
            try? MCPInstaller.uninstall(config)
        }
        await removeServer(id: id)
    }

    // MARK: - Private

    private func connectServer(_ config: MCPServerConfig) async {
        let connection = MCPConnection(config: config)
        connections[config.id] = connection
        await connection.connect()

        if connection.status.isConnected {
            registerTools(for: connection)
        }
    }

    private func registerTools(for connection: MCPConnection) {
        guard let registry = toolRegistry else { return }
        for mcpTool in connection.discoveredTools {
            let adapter = MCPToolAdapter(
                serverName: connection.config.name,
                mcpTool: mcpTool,
                connection: connection
            )
            registry.register(adapter)
        }
    }

    private func unregisterTools(for connection: MCPConnection) {
        guard let registry = toolRegistry else { return }
        registry.unregisterAll(prefix: "\(connection.config.name).")
    }
}
