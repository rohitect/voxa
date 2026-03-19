import Foundation
import MCP

/// Lifecycle manager for all MCP server connections.
/// Owns connections, persists config, and registers/unregisters tools in ToolRegistry.
@Observable
final class MCPManager {
    let configStore: MCPServerConfigStore

    private(set) var connections: [String: MCPConnection] = [:]
    private weak var toolRegistry: ToolRegistry?

    init(toolRegistry: ToolRegistry) {
        self.toolRegistry = toolRegistry
        self.configStore = MCPServerConfigStore()
    }

    // MARK: - Lifecycle

    func connectAll() async {
        for config in configStore.servers where config.enabled {
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
