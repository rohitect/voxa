import AppKit
import Foundation

struct SystemSettingsTool: AgentTool {
    let name = "system_settings"
    let description = "Opens a specific pane in macOS System Settings."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "pane",
            type: "string",
            description: "The settings pane to open.",
            enumValues: [
                "general", "appearance", "accessibility", "privacy", "network",
                "bluetooth", "sound", "displays", "keyboard", "trackpad",
                "battery", "notifications", "focus", "wallpaper",
            ]
        ),
    ]

    private static let paneURLs: [String: String] = [
        "general": "x-apple.systempreferences:com.apple.General-Settings.extension",
        "appearance": "x-apple.systempreferences:com.apple.Appearance-Settings.extension",
        "accessibility": "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
        "privacy": "x-apple.systempreferences:com.apple.Privacy-Settings.extension",
        "network": "x-apple.systempreferences:com.apple.Network-Settings.extension",
        "bluetooth": "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension",
        "sound": "x-apple.systempreferences:com.apple.Sound-Settings.extension",
        "displays": "x-apple.systempreferences:com.apple.Displays-Settings.extension",
        "keyboard": "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "trackpad": "x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
        "battery": "x-apple.systempreferences:com.apple.Battery-Settings.extension",
        "notifications": "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        "focus": "x-apple.systempreferences:com.apple.Focus-Settings.extension",
        "wallpaper": "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let pane = arguments["pane"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'pane'")
        }

        guard let urlString = Self.paneURLs[pane],
              let url = URL(string: urlString) else {
            throw ToolError.invalidArguments("Unknown pane: \(pane)")
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if opened {
            return .success("Opened System Settings > \(pane)")
        } else {
            return .error("Failed to open System Settings pane: \(pane)")
        }
    }
}
