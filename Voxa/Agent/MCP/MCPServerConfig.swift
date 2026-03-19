import Foundation

// MARK: - Transport Type

enum MCPTransportType: String, Codable, Sendable {
    case stdio
    case http
}

// MARK: - Server Config

struct MCPServerConfig: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var enabled: Bool
    var transport: MCPTransportType

    // stdio transport
    var command: String?
    var args: [String]?
    var env: [String: String]?

    // http transport
    var url: String?

    init(id: String = UUID().uuidString, name: String, enabled: Bool = true, transport: MCPTransportType,
         command: String? = nil, args: [String]? = nil, env: [String: String]? = nil, url: String? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
    }
}

// MARK: - Config File Model

private struct MCPConfigFile: Codable {
    var servers: [MCPServerConfig]
}

// MARK: - Config Store

@Observable
final class MCPServerConfigStore {
    private(set) var servers: [MCPServerConfig] = []

    private let fileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".voxa/mcp-servers.json")
    }()

    init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            servers = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)
            servers = config.servers
        } catch {
            print("[MCPConfigStore] Failed to load config: \(error)")
            servers = []
        }
    }

    func save() {
        let config = MCPConfigFile(servers: servers)
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[MCPConfigStore] Failed to save config: \(error)")
        }
    }

    func add(_ server: MCPServerConfig) {
        servers.append(server)
        save()
    }

    func remove(id: String) {
        servers.removeAll { $0.id == id }
        save()
    }

    func update(_ server: MCPServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            save()
        }
    }

    func server(id: String) -> MCPServerConfig? {
        servers.first { $0.id == id }
    }
}
