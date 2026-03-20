import CoreGraphics
import Foundation

struct MouseTool: AgentTool {
    let name = "mouse"
    let description = "Mouse actions: drag between two points, scroll in any direction, or hover (move cursor) to a position."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The mouse action to perform.",
            enumValues: ["drag", "scroll", "hover"]
        ),
        ToolParameter(
            name: "x",
            type: "number",
            description: "X coordinate (destination for hover, start for drag).",
            required: false
        ),
        ToolParameter(
            name: "y",
            type: "number",
            description: "Y coordinate (destination for hover, start for drag).",
            required: false
        ),
        ToolParameter(
            name: "to_x",
            type: "number",
            description: "Destination X coordinate (drag only).",
            required: false
        ),
        ToolParameter(
            name: "to_y",
            type: "number",
            description: "Destination Y coordinate (drag only).",
            required: false
        ),
        ToolParameter(
            name: "direction",
            type: "string",
            description: "Scroll direction.",
            required: false,
            enumValues: ["up", "down", "left", "right"]
        ),
        ToolParameter(
            name: "amount",
            type: "integer",
            description: "Scroll amount in lines (default 3).",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "drag":
            return try performDrag(arguments: arguments)
        case "scroll":
            return try performScroll(arguments: arguments)
        case "hover":
            return try performHover(arguments: arguments)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - Drag

    private func performDrag(arguments: [String: Any]) throws -> ToolResult {
        let startX = try extractCoordinate(arguments, key: "x", label: "x")
        let startY = try extractCoordinate(arguments, key: "y", label: "y")
        let endX = try extractCoordinate(arguments, key: "to_x", label: "to_x")
        let endY = try extractCoordinate(arguments, key: "to_y", label: "to_y")

        let start = CGPoint(x: startX, y: startY)
        let end = CGPoint(x: endX, y: endY)

        // Mouse down at start
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)

        // Dragged (move while button held)
        let mouseDrag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left)
        mouseDrag?.post(tap: .cghidEventTap)

        // Mouse up at end
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        mouseUp?.post(tap: .cghidEventTap)

        return .success("Dragged from (\(Int(startX)), \(Int(startY))) to (\(Int(endX)), \(Int(endY)))")
    }

    // MARK: - Scroll

    private func performScroll(arguments: [String: Any]) throws -> ToolResult {
        guard let direction = arguments["direction"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'direction' for scroll")
        }

        let amount: Int32
        if let a = arguments["amount"] as? Int {
            amount = Int32(a)
        } else if let a = arguments["amount"] as? Double {
            amount = Int32(a)
        } else {
            amount = 3
        }

        let (deltaY, deltaX): (Int32, Int32) = switch direction {
        case "up":    (amount, 0)
        case "down":  (-amount, 0)
        case "left":  (0, amount)
        case "right": (0, -amount)
        default:
            throw ToolError.invalidArguments("Invalid direction '\(direction)'. Use up, down, left, or right.")
        }

        // wheelCount=2 for vertical+horizontal, wheel3=0 required by API
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil, units: .line,
            wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0
        )
        scrollEvent?.post(tap: .cgSessionEventTap)

        return .success("Scrolled \(direction) by \(amount) lines")
    }

    // MARK: - Hover

    private func performHover(arguments: [String: Any]) throws -> ToolResult {
        let x = try extractCoordinate(arguments, key: "x", label: "x")
        let y = try extractCoordinate(arguments, key: "y", label: "y")

        let point = CGPoint(x: x, y: y)
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)

        return .success("Moved cursor to (\(Int(x)), \(Int(y)))")
    }

    // MARK: - Helpers

    private func extractCoordinate(_ arguments: [String: Any], key: String, label: String) throws -> CGFloat {
        if let num = arguments[key] as? Double {
            return CGFloat(num)
        } else if let num = arguments[key] as? Int {
            return CGFloat(num)
        }
        throw ToolError.invalidArguments("Missing required parameter '\(label)'")
    }
}
