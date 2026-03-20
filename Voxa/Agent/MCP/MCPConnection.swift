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
    // Keep pipes alive so their file descriptors remain valid for StdioTransport
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

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
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
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

            // Resolve {MCP_ROOT} placeholder to the managed directory path
            let mcpRoot = config.managedDirectory?.path ?? ""
            let resolvedCommand = command.replacingOccurrences(of: "{MCP_ROOT}", with: mcpRoot)
            let resolvedArgs = (config.args ?? []).map {
                $0.replacingOccurrences(of: "{MCP_ROOT}", with: mcpRoot)
            }

            // Launch the MCP server as a subprocess
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [resolvedCommand] + resolvedArgs

            // Always set up environment with Homebrew PATH for finding node/python
            var environment = ProcessInfo.processInfo.environment
            if let path = environment["PATH"] {
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
            }
            if let env = config.env {
                for (key, value) in env {
                    environment[key] = value.replacingOccurrences(of: "{MCP_ROOT}", with: mcpRoot)
                }
            }
            process.environment = environment

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            // Log stderr from MCP server for debugging
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    let name = self?.config.name ?? "?"
                    print("[MCP:\(name)] \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }

            try process.run()
            self.serverProcess = process
            // Keep pipes alive so file descriptors remain valid
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr

            // Create StdioTransport using the process pipes' file descriptors
            let inputFD = stdout.fileHandleForReading.fileDescriptor
            let outputFD = stdin.fileHandleForWriting.fileDescriptor
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
        // Clean up any previous process/pipes before retrying
        serverProcess?.terminate()
        serverProcess = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        client = nil
        transport = nil

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
