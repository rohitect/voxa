import Foundation

struct ShortcutsTool: AgentTool {
    let name = "shortcuts"
    let description = "Run a Shortcuts.app shortcut or an Automator workflow by name or path."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform.",
            enumValues: ["run_shortcut", "list_shortcuts", "run_automator"]
        ),
        ToolParameter(
            name: "name",
            type: "string",
            description: "Name of the shortcut (for run_shortcut) or path to the Automator workflow (for run_automator).",
            required: false
        ),
        ToolParameter(
            name: "input",
            type: "string",
            description: "Input text to pass to the shortcut or workflow.",
            required: false
        ),
        ToolParameter(
            name: "timeout",
            type: "integer",
            description: "Timeout in seconds (default 30).",
            required: false
        ),
    ]

    let requiresConfirmation = true

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "run_shortcut":
            return try await runShortcut(arguments: arguments)
        case "list_shortcuts":
            return await listShortcuts()
        case "run_automator":
            return try await runAutomator(arguments: arguments)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - Run Shortcut

    private func runShortcut(arguments: [String: Any]) async throws -> ToolResult {
        guard let name = arguments["name"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'name' for run_shortcut")
        }
        let input = arguments["input"] as? String
        let timeout = extractTimeout(arguments)

        var args = ["run", name]
        if let input {
            args += ["--input-type", "text", "--input", input]
        }

        return await runProcess(
            path: "/usr/bin/shortcuts",
            arguments: args,
            timeout: timeout,
            label: "Shortcut '\(name)'"
        )
    }

    // MARK: - List Shortcuts

    private func listShortcuts() async -> ToolResult {
        return await runProcess(
            path: "/usr/bin/shortcuts",
            arguments: ["list"],
            timeout: 10,
            label: "Shortcuts list"
        )
    }

    // MARK: - Run Automator

    private func runAutomator(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["name"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'name' (workflow path) for run_automator")
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        let input = arguments["input"] as? String
        let timeout = extractTimeout(arguments)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .error("Workflow not found: \(expandedPath)")
        }

        var args = [expandedPath]
        if let input {
            args += ["-i", input]
        }

        return await runProcess(
            path: "/usr/bin/automator",
            arguments: args,
            timeout: timeout,
            label: "Automator workflow"
        )
    }

    // MARK: - Helpers

    private func extractTimeout(_ arguments: [String: Any]) -> Int {
        (arguments["timeout"] as? Int) ?? (arguments["timeout"] as? Double).map { Int($0) } ?? 30
    }

    private func runProcess(path: String, arguments: [String], timeout: Int, label: String) async -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .error("Failed to start \(label): \(error.localizedDescription)")
        }

        let completed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let deadline = DispatchTime.now() + .seconds(timeout)
                let group = DispatchGroup()
                group.enter()

                DispatchQueue.global().async {
                    process.waitUntilExit()
                    group.leave()
                }

                let result = group.wait(timeout: deadline)
                if result == .timedOut {
                    process.terminate()
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if !completed {
            return .error("\(label) timed out after \(timeout) seconds.\nPartial output: \(truncate(stdout))")
        }

        let exitCode = process.terminationStatus
        var output = ""

        if !stdout.isEmpty { output += stdout }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "stderr: \(stderr)"
        }

        if output.isEmpty {
            output = "(no output)"
        }

        output = truncate(output)

        if exitCode != 0 {
            return .error("\(label) failed (exit \(exitCode))\n\(output)")
        }

        return .success(output)
    }

    private func truncate(_ text: String, maxLength: Int = 4000) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "\n...(truncated)"
    }
}
