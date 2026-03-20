import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowManagementTool: AgentTool {
    let name = "window_management"
    let description = "List, focus, minimize, close, and resize windows, or open URLs and files."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform: list_windows, focus_window, minimize_window, close_window, resize_window, open_url, open_file.",
            enumValues: ["list_windows", "focus_window", "minimize_window", "close_window", "resize_window", "open_url", "open_file"]
        ),
        ToolParameter(
            name: "window_id",
            type: "integer",
            description: "Window ID from list_windows (for focus_window, resize_window).",
            required: false
        ),
        ToolParameter(
            name: "app_name",
            type: "string",
            description: "App name to filter windows or identify target (for focus_window, resize_window).",
            required: false
        ),
        ToolParameter(
            name: "x",
            type: "number",
            description: "New window X position (for resize_window).",
            required: false
        ),
        ToolParameter(
            name: "y",
            type: "number",
            description: "New window Y position (for resize_window).",
            required: false
        ),
        ToolParameter(
            name: "width",
            type: "number",
            description: "New window width (for resize_window).",
            required: false
        ),
        ToolParameter(
            name: "height",
            type: "number",
            description: "New window height (for resize_window).",
            required: false
        ),
        ToolParameter(
            name: "url",
            type: "string",
            description: "URL to open (for open_url).",
            required: false
        ),
        ToolParameter(
            name: "path",
            type: "string",
            description: "File path to open (for open_file).",
            required: false
        ),
        ToolParameter(
            name: "with_app",
            type: "string",
            description: "App name to open the file with (for open_file). If omitted, uses default app.",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "list_windows":
            return listWindows(arguments: arguments)
        case "focus_window":
            return try await focusWindow(arguments: arguments)
        case "minimize_window":
            return try await minimizeWindow(arguments: arguments)
        case "close_window":
            return try await closeWindow(arguments: arguments)
        case "resize_window":
            return try await resizeWindow(arguments: arguments)
        case "open_url":
            return try await openURL(arguments: arguments)
        case "open_file":
            return try await openFile(arguments: arguments)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - List Windows

    private func listWindows(arguments: [String: Any]) -> ToolResult {
        let filterApp = arguments["app_name"] as? String

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return .error("Failed to retrieve window list")
        }

        var output = ""
        var count = 0

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let windowID = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue } // layer 0 = normal windows

            // Filter by app name if specified
            if let filterApp, !ownerName.lowercased().contains(filterApp.lowercased()) {
                continue
            }

            let title = window[kCGWindowName as String] as? String ?? "(untitled)"
            let x = bounds["X"] as? Int ?? 0
            let y = bounds["Y"] as? Int ?? 0
            let w = bounds["Width"] as? Int ?? 0
            let h = bounds["Height"] as? Int ?? 0

            output += "[\(windowID)] \(ownerName) — \"\(title)\" (\(x),\(y) \(w)x\(h))\n"
            count += 1
        }

        if count == 0 {
            let qualifier = filterApp.map { " for '\($0)'" } ?? ""
            return .success("No windows found\(qualifier)")
        }

        return .success("\(count) window(s):\n\(output)")
    }

    // MARK: - Focus Window

    private func focusWindow(arguments: [String: Any]) async throws -> ToolResult {
        // Find the target window by ID or app name
        guard let (ownerPID, ownerName, windowElement) = try findTargetWindow(arguments: arguments) else {
            return .error("Window not found. Use list_windows to see available windows.")
        }

        // Activate the owning application
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            await MainActor.run {
                app.activate()
            }
        }

        // Raise the window via AX API
        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)

        // Give the OS time to finish activating the window so subsequent
        // keyboard/mouse actions target the correct app.
        try await Task.sleep(for: .milliseconds(300))

        return .success("Focused window of \(ownerName)")
    }

    // MARK: - Minimize Window

    private func minimizeWindow(arguments: [String: Any]) async throws -> ToolResult {
        guard let (_, ownerName, windowElement) = try findTargetWindow(arguments: arguments) else {
            return .error("Window not found. Use list_windows to see available windows.")
        }

        let result = AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        if result == .success {
            return .success("Minimized window of \(ownerName)")
        } else {
            return .error("Failed to minimize window of \(ownerName) (AX error \(result.rawValue)). The app may not support programmatic minimize.")
        }
    }

    // MARK: - Close Window

    private func closeWindow(arguments: [String: Any]) async throws -> ToolResult {
        guard let (_, ownerName, windowElement) = try findTargetWindow(arguments: arguments) else {
            return .error("Window not found. Use list_windows to see available windows.")
        }

        // Get the close button from the window element
        var closeButtonRef: AnyObject?
        let attrResult = AXUIElementCopyAttributeValue(windowElement, kAXCloseButtonAttribute as CFString, &closeButtonRef)
        guard attrResult == .success, let closeButton = closeButtonRef else {
            return .error("Cannot close window of \(ownerName) — no close button accessible via AX API.")
        }

        let pressResult = AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        if pressResult == .success {
            return .success("Closed window of \(ownerName)")
        } else {
            return .error("Failed to close window of \(ownerName) (AX error \(pressResult.rawValue)).")
        }
    }

    // MARK: - Resize Window

    private func resizeWindow(arguments: [String: Any]) async throws -> ToolResult {
        guard let (_, ownerName, windowElement) = try findTargetWindow(arguments: arguments) else {
            return .error("Window not found. Use list_windows to see available windows.")
        }

        var changes: [String] = []

        // Set position if provided
        let newX = extractOptionalCoordinate(arguments, key: "x")
        let newY = extractOptionalCoordinate(arguments, key: "y")
        if let x = newX, let y = newY {
            var point = CGPoint(x: x, y: y)
            let pointValue = AXValueCreate(.cgPoint, &point)!
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, pointValue)
            changes.append("position (\(Int(x)),\(Int(y)))")
        }

        // Set size if provided
        let newW = extractOptionalCoordinate(arguments, key: "width")
        let newH = extractOptionalCoordinate(arguments, key: "height")
        if let w = newW, let h = newH {
            var size = CGSize(width: w, height: h)
            let sizeValue = AXValueCreate(.cgSize, &size)!
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
            changes.append("size \(Int(w))x\(Int(h))")
        }

        if changes.isEmpty {
            return .error("Provide x+y (position) and/or width+height (size) to resize.")
        }

        return .success("Updated \(ownerName) window: \(changes.joined(separator: ", "))")
    }

    // MARK: - Open URL

    private func openURL(arguments: [String: Any]) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'url' for open_url")
        }

        guard let url = URL(string: urlString) else {
            return .error("Invalid URL: \(urlString)")
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if opened {
            return .success("Opened \(urlString)")
        } else {
            return .error("Failed to open \(urlString)")
        }
    }

    // MARK: - Open File

    private func openFile(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'path' for open_file")
        }

        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .error("File not found: \(path)")
        }

        if let withApp = arguments["with_app"] as? String {
            // Open with specific app
            guard let appURL = findAppURL(withApp) else {
                return .error("Application '\(withApp)' not found")
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            do {
                try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
                return .success("Opened \(path) with \(withApp)")
            } catch {
                return .error("Failed to open \(path) with \(withApp): \(error.localizedDescription)")
            }
        } else {
            // Open with default app
            let opened = await MainActor.run {
                NSWorkspace.shared.open(fileURL)
            }
            if opened {
                return .success("Opened \(path)")
            } else {
                return .error("Failed to open \(path)")
            }
        }
    }

    // MARK: - Helpers

    private func findTargetWindow(arguments: [String: Any]) throws -> (pid: pid_t, ownerName: String, element: AXUIElement)? {
        let windowID = arguments["window_id"] as? Int ?? (arguments["window_id"] as? Double).map { Int($0) }
        let appName = arguments["app_name"] as? String

        guard windowID != nil || appName != nil else {
            throw ToolError.invalidArguments("Provide 'window_id' or 'app_name' to identify the target window.")
        }

        // Try both on-screen and all windows (minimized windows aren't on-screen)
        let listOptions: [CGWindowListOption] = [
            [.optionOnScreenOnly, .excludeDesktopElements],
            [.optionAll, .excludeDesktopElements],
        ]

        for options in listOptions {
            guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                continue
            }

            for window in windowList {
                guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                      let wID = window[kCGWindowNumber as String] as? Int,
                      let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                      let layer = window[kCGWindowLayer as String] as? Int,
                      layer == 0 else { continue }

                let matches: Bool
                if let windowID {
                    matches = wID == windowID
                } else if let appName {
                    matches = ownerName.lowercased().contains(appName.lowercased())
                } else {
                    matches = false
                }

                guard matches else { continue }

                // Get the AX window element
                let pid = pid_t(ownerPID)
                let appElement = AXUIElementCreateApplication(pid)
                var windowsRef: AnyObject?
                let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
                guard result == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

                // Match by window title or just use the first window
                let windowTitle = window[kCGWindowName as String] as? String
                let axWindow = axWindows.first { axWin in
                    if let windowTitle {
                        var titleRef: AnyObject?
                        AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                        return (titleRef as? String) == windowTitle
                    }
                    return true
                } ?? axWindows.first

                guard let axWindow else { continue }
                return (pid: pid, ownerName: ownerName, element: axWindow)
            }
        }

        return nil
    }

    private func extractOptionalCoordinate(_ arguments: [String: Any], key: String) -> CGFloat? {
        if let num = arguments[key] as? Double {
            return CGFloat(num)
        } else if let num = arguments[key] as? Int {
            return CGFloat(num)
        }
        return nil
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
                if url.deletingPathExtension().lastPathComponent.lowercased() == lowercaseName {
                    return url
                }
            }
        }
        return nil
    }
}
