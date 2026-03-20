import AppKit
import Foundation
import UserNotifications

struct NotificationTool: AgentTool {
    let name = "notification"
    let description = "Show notifications or alert dialogs to the user."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform.",
            enumValues: ["send_notification", "alert"]
        ),
        ToolParameter(
            name: "title",
            type: "string",
            description: "Title of the notification or alert."
        ),
        ToolParameter(
            name: "message",
            type: "string",
            description: "Body text of the notification or alert.",
            required: false
        ),
        ToolParameter(
            name: "style",
            type: "string",
            description: "Alert style (for alert action): informational, warning, or critical.",
            required: false,
            enumValues: ["informational", "warning", "critical"]
        ),
        ToolParameter(
            name: "buttons",
            type: "string",
            description: "Comma-separated button labels for alert (default: 'OK'). First button is the primary action.",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "send_notification":
            return await sendNotification(arguments: arguments)
        case "alert":
            return await showAlert(arguments: arguments)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - Send Notification

    private func sendNotification(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String else {
            return .error("Missing required parameter 'title'")
        }
        let message = arguments["message"] as? String

        let content = UNMutableNotificationContent()
        content.title = title
        if let message { content.body = message }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        do {
            let center = UNUserNotificationCenter.current()

            // Request permission if needed
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                return .error("Notification permission not granted. Enable notifications for Voxa in System Settings.")
            }

            try await center.add(request)
            return .success("Notification sent: \(title)")
        } catch {
            return .error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Show Alert

    private func showAlert(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String else {
            return .error("Missing required parameter 'title'")
        }
        let message = arguments["message"] as? String
        let style = arguments["style"] as? String ?? "informational"
        let buttonsStr = arguments["buttons"] as? String

        let buttonLabels: [String]
        if let buttonsStr, !buttonsStr.isEmpty {
            buttonLabels = buttonsStr.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        } else {
            buttonLabels = ["OK"]
        }

        let alertStyle: NSAlert.Style = switch style {
        case "warning": .warning
        case "critical": .critical
        default: .informational
        }

        let clickedButton = await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            if let message { alert.informativeText = message }
            alert.alertStyle = alertStyle

            for label in buttonLabels {
                alert.addButton(withTitle: label)
            }

            // Bring app to front so alert is visible
            NSApp.activate(ignoringOtherApps: true)

            let response = alert.runModal()
            // NSAlertFirstButtonReturn = 1000, second = 1001, etc.
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if index >= 0 && index < buttonLabels.count {
                return buttonLabels[index]
            }
            return buttonLabels.first ?? "OK"
        }

        return .success("User clicked: \(clickedButton)")
    }
}
