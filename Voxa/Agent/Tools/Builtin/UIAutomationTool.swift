import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct UIAutomationTool: AgentTool {
    let name = "ui_automation"
    let description = "Interact with UI elements: click, type text, read element information, list menu items, or get selected text."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The UI action to perform.",
            enumValues: ["click", "type", "read_element", "list_elements", "get_focused_element", "list_menu_items", "get_selected_text"]
        ),
        ToolParameter(
            name: "x",
            type: "number",
            description: "X coordinate for click action.",
            required: false
        ),
        ToolParameter(
            name: "y",
            type: "number",
            description: "Y coordinate for click action.",
            required: false
        ),
        ToolParameter(
            name: "text",
            type: "string",
            description: "Text to type (for type action).",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard AXIsProcessTrusted() else {
            return .error("Accessibility permission not granted. Please enable Voxa in System Settings > Privacy & Security > Accessibility.")
        }

        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "click":
            return try performClick(arguments: arguments)
        case "type":
            return try performType(arguments: arguments)
        case "read_element":
            return readFocusedElement()
        case "list_elements":
            return listElements()
        case "get_focused_element":
            return readFocusedElement()
        case "list_menu_items":
            return listMenuItems()
        case "get_selected_text":
            return getSelectedText()
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    private func performClick(arguments: [String: Any]) throws -> ToolResult {
        let x: CGFloat
        let y: CGFloat

        if let xNum = arguments["x"] as? Double {
            x = CGFloat(xNum)
        } else if let xNum = arguments["x"] as? Int {
            x = CGFloat(xNum)
        } else {
            throw ToolError.invalidArguments("Missing required parameter 'x' for click")
        }

        if let yNum = arguments["y"] as? Double {
            y = CGFloat(yNum)
        } else if let yNum = arguments["y"] as? Int {
            y = CGFloat(yNum)
        } else {
            throw ToolError.invalidArguments("Missing required parameter 'y' for click")
        }

        let point = CGPoint(x: x, y: y)

        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)

        return .success("Clicked at (\(Int(x)), \(Int(y)))")
    }

    private func performType(arguments: [String: Any]) throws -> ToolResult {
        guard let text = arguments["text"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'text' for type action")
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            let str = String(char)
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: str.utf16.count, unicodeString: Array(str.utf16))
            event?.post(tap: .cghidEventTap)

            let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            eventUp?.post(tap: .cghidEventTap)
        }

        return .success("Typed \(text.count) characters")
    }

    private func readFocusedElement() -> ToolResult {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return .success("No focused element found")
        }

        let info = describeElement(element as! AXUIElement)
        return .success(info)
    }

    private func listElements() -> ToolResult {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .error("No frontmost application")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var children: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &children)

        guard result == .success, let windows = children as? [AXUIElement], let mainWindow = windows.first else {
            return .success("No accessible windows found for \(app.localizedName ?? "app")")
        }

        var output = "Elements in \(app.localizedName ?? "app"):\n"
        walkTree(element: mainWindow, depth: 0, maxDepth: 3, output: &output)
        return .success(output)
    }

    private func listMenuItems() -> ToolResult {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .error("No frontmost application")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef)

        guard result == .success, let menuBar = menuBarRef else {
            return .success("No menu bar accessible for \(app.localizedName ?? "app")")
        }

        let menuBarElement = menuBar as! AXUIElement
        var output = "Menu items for \(app.localizedName ?? "app"):\n"
        walkMenuTree(element: menuBarElement, depth: 0, maxDepth: 2, output: &output)
        return .success(output)
    }

    private func walkMenuTree(element: AXUIElement, depth: Int, maxDepth: Int, output: inout String) {
        guard depth <= maxDepth else { return }

        var childrenRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else { return }

        let indent = String(repeating: "  ", count: depth)

        for child in children {
            let role = getAttribute(child, kAXRoleAttribute) ?? ""
            let title = getAttribute(child, kAXTitleAttribute) ?? ""
            let enabled = getAttribute(child, kAXEnabledAttribute)

            // Skip separators and empty items
            if title.isEmpty && role != "AXMenuBarItem" && role != "AXMenu" { continue }

            if !title.isEmpty {
                var line = "\(indent)- \(title)"
                if enabled == "0" { line += " (disabled)" }
                output += line + "\n"
            }

            // Recurse into submenus
            walkMenuTree(element: child, depth: depth + 1, maxDepth: maxDepth, output: &output)
        }
    }

    private func getSelectedText() -> ToolResult {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard result == .success, let focused = focusedRef else {
            return .success("No focused element found")
        }

        let element = focused as! AXUIElement
        var selectedTextRef: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)

        guard textResult == .success, let selectedText = selectedTextRef as? String else {
            return .success("No text selected (or element doesn't support text selection)")
        }

        if selectedText.isEmpty {
            return .success("No text selected")
        }

        return .success(selectedText)
    }

    private func walkTree(element: AXUIElement, depth: Int, maxDepth: Int, output: inout String) {
        guard depth <= maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)
        let desc = describeElementBrief(element)
        output += "\(indent)- \(desc)\n"

        var children: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard result == .success, let childElements = children as? [AXUIElement] else { return }

        for child in childElements.prefix(20) {
            walkTree(element: child, depth: depth + 1, maxDepth: maxDepth, output: &output)
        }
    }

    private func describeElement(_ element: AXUIElement) -> String {
        var parts: [String] = []

        if let role = getAttribute(element, kAXRoleAttribute) { parts.append("Role: \(role)") }
        if let title = getAttribute(element, kAXTitleAttribute) { parts.append("Title: \(title)") }
        if let value = getAttribute(element, kAXValueAttribute) { parts.append("Value: \(value)") }
        if let desc = getAttribute(element, kAXDescriptionAttribute) { parts.append("Description: \(desc)") }
        if let roleDesc = getAttribute(element, kAXRoleDescriptionAttribute) { parts.append("RoleDescription: \(roleDesc)") }

        return parts.isEmpty ? "(unknown element)" : parts.joined(separator: ", ")
    }

    private func describeElementBrief(_ element: AXUIElement) -> String {
        let role = getAttribute(element, kAXRoleAttribute) ?? "unknown"
        let title = getAttribute(element, kAXTitleAttribute)
        let desc = getAttribute(element, kAXDescriptionAttribute)

        var label = role
        if let t = title, !t.isEmpty { label += " \"\(t)\"" }
        else if let d = desc, !d.isEmpty { label += " \"\(d)\"" }
        return label
    }

    private func getAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return "\(value!)"
    }
}
