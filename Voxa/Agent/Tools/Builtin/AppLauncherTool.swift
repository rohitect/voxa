import AppKit
import Foundation

struct AppLauncherTool: AgentTool {
    let name = "app_launcher"
    let description = "Open, switch to, or quit a macOS application."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform.",
            enumValues: ["open", "switch", "quit"]
        ),
        ToolParameter(
            name: "app_name",
            type: "string",
            description: "The name of the application (e.g. 'Safari', 'Calculator')."
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }
        guard let appName = arguments["app_name"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'app_name'")
        }

        switch action {
        case "open":
            return try await openApp(appName)
        case "switch":
            return try await switchToApp(appName)
        case "quit":
            return try await quitApp(appName)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    private func openApp(_ name: String) async throws -> ToolResult {
        guard let appURL = findAppURL(name) else {
            return .error("Application '\(name)' not found")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        do {
            let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return .success("Opened \(app.localizedName ?? name)")
        } catch {
            return .error("Failed to open \(name): \(error.localizedDescription)")
        }
    }

    private func switchToApp(_ name: String) async throws -> ToolResult {
        guard let app = findRunningApp(name) else {
            // If not running, open it instead
            return try await openApp(name)
        }

        let activated = await MainActor.run {
            app.activate()
        }

        if activated {
            return .success("Switched to \(app.localizedName ?? name)")
        } else {
            return .error("Failed to switch to \(name)")
        }
    }

    private func quitApp(_ name: String) async throws -> ToolResult {
        guard let app = findRunningApp(name) else {
            return .error("Application '\(name)' is not running")
        }

        let terminated = app.terminate()
        if terminated {
            return .success("Quit \(app.localizedName ?? name)")
        } else {
            return .error("Failed to quit \(name). It may require Force Quit.")
        }
    }

    private func findAppURL(_ name: String) -> URL? {
        let searchDirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]

        let lowercaseName = name.lowercased()

        for dir in searchDirs {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil
            ) else { continue }

            for url in contents {
                let appFileName = url.deletingPathExtension().lastPathComponent.lowercased()
                if appFileName == lowercaseName {
                    return url
                }
            }
        }

        // Fallback: try constructing the path directly
        for dir in searchDirs {
            let url = URL(fileURLWithPath: "\(dir)/\(name).app")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func findRunningApp(_ name: String) -> NSRunningApplication? {
        let lowercaseName = name.lowercased()
        return NSWorkspace.shared.runningApplications.first { app in
            if let localizedName = app.localizedName?.lowercased(), localizedName == lowercaseName {
                return true
            }
            if let bundleId = app.bundleIdentifier?.lowercased(), bundleId.contains(lowercaseName) {
                return true
            }
            return false
        }
    }
}
