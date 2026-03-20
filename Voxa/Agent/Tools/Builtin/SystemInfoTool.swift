import AppKit
import Foundation

struct SystemInfoTool: AgentTool {
    let name = "system_info"
    let description = "Get system information, list running processes, or terminate a process."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform.",
            enumValues: ["get_system_info", "get_running_processes", "kill_process"]
        ),
        ToolParameter(
            name: "pid",
            type: "integer",
            description: "Process ID to terminate (for kill_process).",
            required: false
        ),
        ToolParameter(
            name: "app_name",
            type: "string",
            description: "Application name to terminate (for kill_process). Alternative to pid.",
            required: false
        ),
        ToolParameter(
            name: "force",
            type: "boolean",
            description: "Force terminate the process (for kill_process, default false).",
            required: false
        ),
    ]

    var requiresConfirmation: Bool { true }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "get_system_info":
            return getSystemInfo()
        case "get_running_processes":
            return getRunningProcesses()
        case "kill_process":
            return try killProcess(arguments: arguments)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - System Info

    private func getSystemInfo() -> ToolResult {
        let info = ProcessInfo.processInfo
        var output = ""

        // OS
        let osVersion = info.operatingSystemVersion
        output += "macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)\n"
        output += "Hostname: \(info.hostName)\n"

        // CPU
        output += "CPU Cores: \(info.processorCount) (\(info.activeProcessorCount) active)\n"

        // Memory
        let totalMemGB = Double(info.physicalMemory) / 1_073_741_824
        output += "Memory: \(String(format: "%.1f", totalMemGB)) GB\n"

        // Uptime
        let uptime = info.systemUptime
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        output += "Uptime: \(days)d \(hours)h \(minutes)m\n"

        // Thermal state
        let thermalState: String = switch info.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
        output += "Thermal: \(thermalState)\n"

        // Low power mode
        output += "Low Power Mode: \(info.isLowPowerModeEnabled ? "Yes" : "No")\n"

        // Disk space (for root volume)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            if let freeBytes = attrs[.systemFreeSize] as? UInt64,
               let totalBytes = attrs[.systemSize] as? UInt64 {
                let freeGB = Double(freeBytes) / 1_073_741_824
                let totalGB = Double(totalBytes) / 1_073_741_824
                let usedGB = totalGB - freeGB
                output += "Disk: \(String(format: "%.1f", usedGB)) / \(String(format: "%.1f", totalGB)) GB used (\(String(format: "%.1f", freeGB)) GB free)\n"
            }
        }

        // Display info
        if let screen = NSScreen.main {
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            output += "Display: \(Int(frame.width))x\(Int(frame.height)) @\(Int(scale))x\n"
        }

        return .success(output)
    }

    // MARK: - Running Processes

    private func getRunningProcesses() -> ToolResult {
        let apps = NSWorkspace.shared.runningApplications

        var output = ""
        var count = 0

        // Group: regular apps first, then background
        let regularApps = apps.filter { $0.activationPolicy == .regular }
        let backgroundApps = apps.filter { $0.activationPolicy == .accessory || $0.activationPolicy == .prohibited }
            .filter { $0.localizedName != nil }

        if !regularApps.isEmpty {
            output += "Applications:\n"
            for app in regularApps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
                let name = app.localizedName ?? "(unknown)"
                let pid = app.processIdentifier
                let active = app.isActive ? " [active]" : ""
                let hidden = app.isHidden ? " [hidden]" : ""
                output += "  [\(pid)] \(name)\(active)\(hidden)\n"
                count += 1
            }
        }

        if !backgroundApps.isEmpty {
            output += "\nBackground (\(backgroundApps.count)):\n"
            for app in backgroundApps.prefix(30).sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
                let name = app.localizedName ?? "(unknown)"
                let pid = app.processIdentifier
                output += "  [\(pid)] \(name)\n"
                count += 1
            }
            if backgroundApps.count > 30 {
                output += "  ... and \(backgroundApps.count - 30) more\n"
            }
        }

        output = "\(count) processes listed\n\n" + output
        return .success(output)
    }

    // MARK: - Kill Process

    private func killProcess(arguments: [String: Any]) throws -> ToolResult {
        let force = arguments["force"] as? Bool ?? false

        // Find the target process by PID or name
        let pid = arguments["pid"] as? Int ?? (arguments["pid"] as? Double).map { Int($0) }
        let appName = arguments["app_name"] as? String

        guard pid != nil || appName != nil else {
            throw ToolError.invalidArguments("Provide 'pid' or 'app_name' to identify the process to terminate.")
        }

        let targetApp: NSRunningApplication?

        if let pid {
            targetApp = NSRunningApplication(processIdentifier: pid_t(pid))
        } else if let appName {
            let lowercaseName = appName.lowercased()
            targetApp = NSWorkspace.shared.runningApplications.first { app in
                if let name = app.localizedName?.lowercased(), name == lowercaseName { return true }
                if let bundleId = app.bundleIdentifier?.lowercased(), bundleId.contains(lowercaseName) { return true }
                return false
            }
        } else {
            targetApp = nil
        }

        guard let app = targetApp else {
            return .error("Process not found. Use get_running_processes to see running processes.")
        }

        let name = app.localizedName ?? "PID \(app.processIdentifier)"

        let terminated: Bool
        if force {
            terminated = app.forceTerminate()
        } else {
            terminated = app.terminate()
        }

        if terminated {
            return .success("\(force ? "Force terminated" : "Terminated") \(name) (PID \(app.processIdentifier))")
        } else {
            return .error("Failed to terminate \(name). Try with force=true.")
        }
    }
}
