import Foundation
import MCP

// MARK: - Connection Status

enum MCPConnectionStatus: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - MCP Connection

@Observable
final class MCPConnection {
    let config: MCPServerConfig

    private(set) var status: MCPConnectionStatus = .disconnected
    private(set) var discoveredTools: [MCP.Tool] = []

    private var client: Client?
    private var transport: (any Transport)?
    private var serverProcess: Process?

    init(config: MCPServerConfig) {
        self.config = config
    }

    func connect() async {
        guard !status.isConnected else { return }
        status = .connecting

        do {
            let (createdClient, createdTransport) = try await createClientAndTransport()
            self.client = createdClient
            self.transport = createdTransport

            _ = try await createdClient.connect(transport: createdTransport)

            let toolsResult = try await createdClient.listTools()
            self.discoveredTools = toolsResult.tools

            status = .connected
            print("[MCPConnection] Connected to '\(config.name)' — \(discoveredTools.count) tools discovered")
        } catch {
            status = .error(error.localizedDescription)
            print("[MCPConnection] Failed to connect to '\(config.name)': \(error)")

            // Auto-retry once after 3s
            try? await Task.sleep(for: .seconds(3))
            if case .error = status {
                await retryConnect()
            }
        }
    }

    func disconnect() async {
        serverProcess?.terminate()
        serverProcess = nil
        client = nil
        transport = nil
        discoveredTools = []
        status = .disconnected
        print("[MCPConnection] Disconnected from '\(config.name)'")
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let client = client, status.isConnected else {
            throw ToolError.executionFailed("MCP server '\(config.name)' is not connected")
        }

        let mcpArgs = MCPTypes.convertArguments(arguments)
        let result = try await client.callTool(name: name, arguments: mcpArgs)

        if result.isError == true {
            let errorText = MCPTypes.extractText(from: result.content)
            throw ToolError.executionFailed(errorText)
        }

        return MCPTypes.extractText(from: result.content)
    }

    // MARK: - Private

    private func createClientAndTransport() async throws -> (Client, any Transport) {
        switch config.transport {
        case .stdio:
            guard let command = config.command, !command.isEmpty else {
                throw ToolError.invalidArguments("No command specified for stdio transport")
            }

            // Launch the MCP server as a subprocess
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + (config.args ?? [])

            if let env = config.env {
                var environment = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    environment[key] = value
                }
                process.environment = environment
            }

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice

            try process.run()
            self.serverProcess = process

            // Create StdioTransport using the process pipes' file descriptors
            let inputFD = stdoutPipe.fileHandleForReading.fileDescriptor
            let outputFD = stdinPipe.fileHandleForWriting.fileDescriptor
            let transport = StdioTransport(
                input: .init(rawValue: inputFD),
                output: .init(rawValue: outputFD)
            )
            let client = Client(name: "Voxa", version: "1.0.0")
            return (client, transport)

        case .http:
            guard let urlString = config.url, let url = URL(string: urlString) else {
                throw ToolError.invalidArguments("Invalid URL for HTTP transport")
            }
            let transport = HTTPClientTransport(endpoint: url)
            let client = Client(name: "Voxa", version: "1.0.0")
            return (client, transport)
        }
    }

    private func retryConnect() async {
        status = .connecting
        do {
            let (createdClient, createdTransport) = try await createClientAndTransport()
            self.client = createdClient
            self.transport = createdTransport

            _ = try await createdClient.connect(transport: createdTransport)

            let toolsResult = try await createdClient.listTools()
            self.discoveredTools = toolsResult.tools
            status = .connected
            print("[MCPConnection] Reconnected to '\(config.name)'")
        } catch {
            status = .error(error.localizedDescription)
            print("[MCPConnection] Retry failed for '\(config.name)': \(error)")
        }
    }
}
