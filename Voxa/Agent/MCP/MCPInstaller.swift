import Foundation

/// Detected project type for an MCP repository.
enum MCPProjectType: String, Sendable {
    case node
    case python
    case unknown
}

/// Result of an MCP installation or update.
struct MCPInstallResult: Sendable {
    let config: MCPServerConfig
    let projectType: MCPProjectType
    let output: String
}

/// Handles cloning, building, and updating MCP server repositories.
/// Repos are stored at ~/.voxa/mcp-repos/<server-id>/
final class MCPInstaller {

    static let reposDirectory: URL = Constants.dataDirectory
        .appendingPathComponent("mcp-repos", isDirectory: true)

    // MARK: - Install from Repository

    /// Clone a git repository, run the build command, derive the execute command,
    /// and return a ready-to-use MCPServerConfig.
    static func install(repository: String, name: String,
                        buildCommand: String? = nil,
                        command: String? = nil, args: [String]? = nil,
                        transport: MCPTransportType = .stdio, url: String? = nil,
                        env: [String: String]? = nil) async throws -> MCPInstallResult {
        let id = UUID().uuidString
        let repoDir = reposDirectory.appendingPathComponent(id, isDirectory: true)

        // Ensure parent directory exists
        try FileManager.default.createDirectory(at: reposDirectory, withIntermediateDirectories: true)

        // Clone
        let cloneOutput = try await runShell("git clone \(shellEscape(repository)) \(shellEscape(repoDir.path))")
        print("[MCPInstaller] Cloned \(repository) → \(repoDir.path)")

        // Detect project type
        let projectType = detectProjectType(at: repoDir)
        print("[MCPInstaller] Detected project type: \(projectType.rawValue)")

        // Resolve build command: user-provided > auto-detected
        let resolvedBuild = resolveBuildCommand(buildCommand, projectType: projectType, dir: repoDir)

        // Run build
        var buildOutput = cloneOutput
        if let build = resolvedBuild {
            let resolved = build.replacingOccurrences(of: "{MCP_ROOT}", with: repoDir.path)
            buildOutput += "\n" + (try await runShell("cd \(shellEscape(repoDir.path)) && \(resolved)"))
        }

        // Resolve execute command: user-provided > auto-detected
        let (resolvedCommand, resolvedArgs) = try resolveExecuteCommand(
            command: command, args: args, projectType: projectType, repoDir: repoDir
        )

        let config = MCPServerConfig(
            id: id,
            name: name,
            enabled: true,
            transport: transport,
            buildCommand: resolvedBuild,
            command: transport == .stdio ? resolvedCommand : nil,
            args: transport == .stdio ? resolvedArgs : nil,
            env: env,
            url: transport == .http ? url : nil,
            repository: repository,
            lastFetched: Date()
        )

        return MCPInstallResult(config: config, projectType: projectType, output: buildOutput)
    }

    // MARK: - Install from Local Path

    /// Copy a local MCP server folder into ~/.voxa/mcp-repos/, run build, and configure.
    static func installFromLocal(path: String, name: String,
                                 buildCommand: String? = nil,
                                 command: String? = nil, args: [String]? = nil,
                                 transport: MCPTransportType = .stdio, url: String? = nil,
                                 env: [String: String]? = nil) async throws -> MCPInstallResult {
        let sourceURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MCPInstallerError.localPathNotFound(path)
        }

        let id = UUID().uuidString
        let destDir = reposDirectory.appendingPathComponent(id, isDirectory: true)

        // Ensure parent directory exists
        try FileManager.default.createDirectory(at: reposDirectory, withIntermediateDirectories: true)

        // Copy the folder
        try FileManager.default.copyItem(at: sourceURL, to: destDir)
        print("[MCPInstaller] Copied \(path) → \(destDir.path)")

        // Detect project type
        let projectType = detectProjectType(at: destDir)
        print("[MCPInstaller] Detected project type: \(projectType.rawValue)")

        // Resolve build command
        let resolvedBuild = resolveBuildCommand(buildCommand, projectType: projectType, dir: destDir)

        // Run build
        var buildOutput = "Copied from \(path)"
        if let build = resolvedBuild {
            let resolved = build.replacingOccurrences(of: "{MCP_ROOT}", with: destDir.path)
            buildOutput += "\n" + (try await runShell("cd \(shellEscape(destDir.path)) && \(resolved)"))
        }

        // Resolve execute command
        let (resolvedCommand, resolvedArgs) = try resolveExecuteCommand(
            command: command, args: args, projectType: projectType, repoDir: destDir
        )

        let config = MCPServerConfig(
            id: id,
            name: name,
            enabled: true,
            transport: transport,
            buildCommand: resolvedBuild,
            command: transport == .stdio ? resolvedCommand : nil,
            args: transport == .stdio ? resolvedArgs : nil,
            env: env,
            url: transport == .http ? url : nil,
            localSource: path,
            lastFetched: Date()
        )

        return MCPInstallResult(config: config, projectType: projectType, output: buildOutput)
    }

    // MARK: - Update (git pull + rebuild)

    /// Pull latest changes and rebuild an existing repo-managed MCP server.
    static func update(_ config: MCPServerConfig) async throws -> MCPInstallResult {
        guard let repository = config.repository else {
            throw MCPInstallerError.notRepoManaged
        }
        guard let repoDir = config.repoDirectory,
              FileManager.default.fileExists(atPath: repoDir.path) else {
            throw MCPInstallerError.repoNotFound
        }

        // Pull
        let pullOutput = try await runShell("cd \(shellEscape(repoDir.path)) && git pull")
        print("[MCPInstaller] Pulled \(repository)")

        // Detect and rebuild
        let projectType = detectProjectType(at: repoDir)

        // Use stored build command or auto-detect
        let resolvedBuild = resolveBuildCommand(config.buildCommand, projectType: projectType, dir: repoDir)

        var buildOutput = pullOutput
        if let build = resolvedBuild {
            let resolved = build.replacingOccurrences(of: "{MCP_ROOT}", with: repoDir.path)
            buildOutput += "\n" + (try await runShell("cd \(shellEscape(repoDir.path)) && \(resolved)"))
        }

        // Re-derive execute command only if not user-specified
        let (resolvedCommand, resolvedArgs) = try resolveExecuteCommand(
            command: config.command, args: config.args, projectType: projectType, repoDir: repoDir
        )

        var updated = config
        updated.buildCommand = resolvedBuild
        updated.command = resolvedCommand
        updated.args = resolvedArgs
        updated.lastFetched = Date()

        return MCPInstallResult(config: updated, projectType: projectType, output: buildOutput)
    }

    // MARK: - Rebuild (run build command only)

    /// Re-run the build command for a managed MCP server without pulling or re-detecting.
    static func rebuild(_ config: MCPServerConfig) async throws -> String {
        guard let dir = config.managedDirectory,
              FileManager.default.fileExists(atPath: dir.path) else {
            throw MCPInstallerError.repoNotFound
        }
        guard let build = config.buildCommand, !build.isEmpty else {
            throw MCPInstallerError.noBuildCommand
        }

        let resolved = build.replacingOccurrences(of: "{MCP_ROOT}", with: dir.path)
        let output = try await runShell("cd \(shellEscape(dir.path)) && \(resolved)")
        print("[MCPInstaller] Rebuilt \(config.name)")
        return output
    }

    // MARK: - Uninstall

    /// Remove the managed MCP directory from disk.
    static func uninstall(_ config: MCPServerConfig) throws {
        guard let dir = config.managedDirectory,
              FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
        print("[MCPInstaller] Removed \(dir.path)")
    }

    // MARK: - Project Detection

    static func detectProjectType(at repoDir: URL) -> MCPProjectType {
        let fm = FileManager.default
        if fm.fileExists(atPath: repoDir.appendingPathComponent("package.json").path) {
            return .node
        }
        if fm.fileExists(atPath: repoDir.appendingPathComponent("pyproject.toml").path) ||
           fm.fileExists(atPath: repoDir.appendingPathComponent("requirements.txt").path) {
            return .python
        }
        return .unknown
    }

    // MARK: - Build Command Resolution

    /// Returns the build command to use: user-provided if non-empty, otherwise auto-detected.
    private static func resolveBuildCommand(_ userBuild: String?, projectType: MCPProjectType, dir: URL) -> String? {
        // If user provided a non-empty build command, use it
        if let userBuild, !userBuild.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Auto-detect
        return deriveBuildCommand(projectType: projectType, dir: dir)
    }

    private static func deriveBuildCommand(projectType: MCPProjectType, dir: URL) -> String? {
        switch projectType {
        case .node:
            return "npm install && npm run build"
        case .python:
            let hasPyproject = FileManager.default.fileExists(atPath: dir.appendingPathComponent("pyproject.toml").path)
            if hasPyproject {
                return "pip install -e ."
            }
            let hasRequirements = FileManager.default.fileExists(atPath: dir.appendingPathComponent("requirements.txt").path)
            if hasRequirements {
                return "pip install -r requirements.txt"
            }
            return nil
        case .unknown:
            return nil
        }
    }

    // MARK: - Execute Command Resolution

    /// Returns the execute command to use: user-provided if non-empty, otherwise auto-detected.
    private static func resolveExecuteCommand(command: String?, args: [String]?, projectType: MCPProjectType, repoDir: URL) throws -> (String, [String]) {
        // If user provided a non-empty command, use it as-is
        if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (command, args ?? [])
        }
        // Auto-detect
        return try deriveEntryPoint(projectType: projectType, repoDir: repoDir)
    }

    // MARK: - Entry Point Detection

    private static func deriveEntryPoint(projectType: MCPProjectType, repoDir: URL) throws -> (command: String, args: [String]) {
        switch projectType {
        case .node:
            return try deriveNodeEntryPoint(repoDir: repoDir)
        case .python:
            return try derivePythonEntryPoint(repoDir: repoDir)
        case .unknown:
            throw MCPInstallerError.cannotDetectEntryPoint
        }
    }

    private static func deriveNodeEntryPoint(repoDir: URL) throws -> (String, [String]) {
        let packageJsonURL = repoDir.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPInstallerError.cannotDetectEntryPoint
        }

        // Check bin field first (e.g., "bin": { "codriver-mcp": "./dist/index.js" })
        if let bin = json["bin"] as? [String: String], let firstBin = bin.values.first {
            return ("node", [repoDir.appendingPathComponent(firstBin).path])
        }
        if let bin = json["bin"] as? String {
            return ("node", [repoDir.appendingPathComponent(bin).path])
        }

        // Check main field
        if let main = json["main"] as? String {
            return ("node", [repoDir.appendingPathComponent(main).path])
        }

        // Common fallbacks
        let fallbacks = ["dist/index.js", "build/index.js", "index.js"]
        for fallback in fallbacks {
            let path = repoDir.appendingPathComponent(fallback).path
            if FileManager.default.fileExists(atPath: path) {
                return ("node", [path])
            }
        }

        throw MCPInstallerError.cannotDetectEntryPoint
    }

    private static func derivePythonEntryPoint(repoDir: URL) throws -> (String, [String]) {
        // Check pyproject.toml for [project.scripts]
        let pyprojectURL = repoDir.appendingPathComponent("pyproject.toml")
        if FileManager.default.fileExists(atPath: pyprojectURL.path),
           let content = try? String(contentsOf: pyprojectURL, encoding: .utf8) {
            // Simple TOML parsing for scripts section
            if let scriptsRange = content.range(of: "[project.scripts]") {
                let afterScripts = content[scriptsRange.upperBound...]
                let lines = afterScripts.components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("[") { break }
                    if trimmed.contains("=") {
                        let scriptName = trimmed.split(separator: "=").first?
                            .trimmingCharacters(in: .whitespaces) ?? ""
                        if !scriptName.isEmpty {
                            return (scriptName, [])
                        }
                    }
                }
            }
        }

        // Fallback: look for common entry points
        let fallbacks = ["main.py", "server.py", "app.py", "src/main.py"]
        for fallback in fallbacks {
            let path = repoDir.appendingPathComponent(fallback).path
            if FileManager.default.fileExists(atPath: path) {
                return ("python3", [path])
            }
        }

        // Fallback: python -m <package_name>
        let srcDir = repoDir.appendingPathComponent("src")
        if let contents = try? FileManager.default.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil),
           let pkg = contents.first(where: { $0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }) {
            return ("python3", ["-m", pkg.lastPathComponent])
        }

        throw MCPInstallerError.cannotDetectEntryPoint
    }

    // MARK: - Shell Execution

    static func runShell(_ command: String, timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            // Inherit user's PATH
            var env = ProcessInfo.processInfo.environment
            if let path = env["PATH"] {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
            }
            process.environment = env

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: MCPInstallerError.shellFailed(error.localizedDescription))
                return
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let combined = (output + "\n" + errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: MCPInstallerError.shellFailed(combined))
            } else {
                continuation.resume(returning: output)
            }
        }
    }

    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Errors

enum MCPInstallerError: Error, LocalizedError {
    case notRepoManaged
    case repoNotFound
    case localPathNotFound(String)
    case cannotDetectEntryPoint
    case noBuildCommand
    case shellFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRepoManaged:
            return "This MCP server is not managed from a repository"
        case .repoNotFound:
            return "Cloned repository not found on disk"
        case .localPathNotFound(let path):
            return "Local path not found: \(path)"
        case .cannotDetectEntryPoint:
            return "Could not detect the entry point for this MCP server. Configure command and args manually."
        case .noBuildCommand:
            return "No build command configured for this MCP server."
        case .shellFailed(let output):
            return "Command failed: \(output.prefix(500))"
        }
    }
}
