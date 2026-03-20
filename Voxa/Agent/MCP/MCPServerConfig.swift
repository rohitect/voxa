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

    // Build step (run once during install/update)
    var buildCommand: String?

    // Execute step — stdio transport
    var command: String?
    var args: [String]?
    var env: [String: String]?

    // Execute step — http transport
    var url: String?

    // Managed MCP source
    var repository: String?
    var localSource: String?
    var lastFetched: Date?

    init(id: String = UUID().uuidString, name: String, enabled: Bool = true, transport: MCPTransportType,
         buildCommand: String? = nil,
         command: String? = nil, args: [String]? = nil, env: [String: String]? = nil, url: String? = nil,
         repository: String? = nil, localSource: String? = nil, lastFetched: Date? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.transport = transport
        self.buildCommand = buildCommand
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.repository = repository
        self.localSource = localSource
        self.lastFetched = lastFetched
    }

    /// Whether this server was installed from a git repository.
    var isRepoManaged: Bool { repository != nil }

    /// Whether this server was copied from a local path.
    var isLocalManaged: Bool { localSource != nil }

    /// Whether Voxa manages the MCP files (repo or local copy).
    var isVoxaManaged: Bool { isRepoManaged || isLocalManaged }

    /// The local directory where the managed MCP lives.
    var managedDirectory: URL? {
        guard isVoxaManaged else { return nil }
        return MCPInstaller.reposDirectory.appendingPathComponent(id, isDirectory: true)
    }

    // Keep backward compat
    var repoDirectory: URL? { managedDirectory }
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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(MCPConfigFile.self, from: data)
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
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)
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
