import Foundation

struct AppleScriptTool: AgentTool {
    let name = "applescript"
    let description = "Execute an AppleScript command via osascript. For multi-line scripts, use the file_write tool to write a .scpt file first, then run it with shell_command 'osascript /path/to/script.scpt'. Useful for controlling Finder, Safari, Mail, Messages, Calendar, Reminders, Music, System Events, and more."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "script",
            type: "string",
            description: "The AppleScript source code to execute."
        ),
        ToolParameter(
            name: "timeout",
            type: "integer",
            description: "Timeout in seconds (default 15).",
            required: false
        ),
    ]

    let requiresConfirmation = true

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let script = arguments["script"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'script'")
        }

        let timeout = (arguments["timeout"] as? Int) ?? (arguments["timeout"] as? Double).map { Int($0) } ?? 15

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .error("Failed to start osascript: \(error.localizedDescription)")
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
            return .error("AppleScript timed out after \(timeout) seconds.\nPartial output: \(truncate(stdout))")
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
            return .error("AppleScript error (exit \(exitCode))\n\(output)")
        }

        return .success(output)
    }

    private func truncate(_ text: String, maxLength: Int = 4000) -> String {
        if text.count <= maxLength { return text }
        let truncated = String(text.prefix(maxLength))
        return truncated + "\n...(truncated)"
    }
}
