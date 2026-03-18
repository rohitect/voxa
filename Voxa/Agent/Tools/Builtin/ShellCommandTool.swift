import Foundation

struct ShellCommandTool: AgentTool {
    let name = "shell_command"
    let description = "Execute a shell command. Requires user confirmation before running."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "command",
            type: "string",
            description: "The shell command to execute."
        ),
        ToolParameter(
            name: "working_directory",
            type: "string",
            description: "Working directory for the command.",
            required: false
        ),
        ToolParameter(
            name: "timeout",
            type: "integer",
            description: "Timeout in seconds (default 10).",
            required: false
        ),
    ]

    let requiresConfirmation = true

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let command = arguments["command"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'command'")
        }

        let workingDir = arguments["working_directory"] as? String
        let timeout = (arguments["timeout"] as? Int) ?? (arguments["timeout"] as? Double).map { Int($0) } ?? 10

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let workingDir = workingDir {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .error("Failed to start process: \(error.localizedDescription)")
        }

        // Wait with timeout
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
            return .error("Command timed out after \(timeout) seconds.\nPartial output: \(truncate(stdout))")
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
            return .error("Exit code \(exitCode)\n\(output)")
        }

        return .success(output)
    }

    private func truncate(_ text: String, maxLength: Int = 4000) -> String {
        if text.count <= maxLength { return text }
        let truncated = String(text.prefix(maxLength))
        return truncated + "\n...(truncated)"
    }
}
