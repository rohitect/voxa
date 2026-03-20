import CoreGraphics
import Foundation

struct KeyboardTool: AgentTool {
    let name = "keyboard"
    let description = "Press key combinations and hotkeys (e.g. Cmd+C, Cmd+Tab, Enter, Escape, arrow keys)."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "key",
            type: "string",
            description: "The key to press (e.g. 'c', 'tab', 'enter', 'escape', 'space', 'delete', 'up', 'down', 'left', 'right', 'f1'-'f12', 'home', 'end', 'pageup', 'pagedown')."
        ),
        ToolParameter(
            name: "modifiers",
            type: "string",
            description: "Comma-separated modifier keys: cmd, shift, alt/option, ctrl/control. Example: 'cmd,shift'.",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let keyName = arguments["key"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'key'")
        }

        guard let keyCode = virtualKeyCode(for: keyName.lowercased()) else {
            return .error("Unknown key: '\(keyName)'. Use key names like 'c', 'tab', 'enter', 'escape', 'up', 'down', 'f1', etc.")
        }

        let modifierFlags = parseModifiers(arguments["modifiers"] as? String)

        let source = CGEventSource(stateID: .hidSystemState)

        // Post modifier key-downs first if needed (some apps require discrete modifier events)
        let modifierKeyCodes = modifierVirtualKeys(modifierFlags)
        for modKey in modifierKeyCodes {
            let modDown = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: true)
            modDown?.flags = modifierFlags
            modDown?.post(tap: .cghidEventTap)
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = modifierFlags
        keyDown?.post(tap: .cghidEventTap)

        // Small delay so the target app registers the keypress
        try await Task.sleep(for: .milliseconds(50))

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = modifierFlags
        keyUp?.post(tap: .cghidEventTap)

        // Release modifier keys
        for modKey in modifierKeyCodes.reversed() {
            let modUp = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: false)
            modUp?.post(tap: .cghidEventTap)
        }

        let modStr = arguments["modifiers"] as? String
        let desc = modStr != nil && !modStr!.isEmpty ? "\(modStr!)+\(keyName)" : keyName
        return .success("Pressed \(desc)")
    }

    // MARK: - Modifier Parsing

    private func parseModifiers(_ modifiers: String?) -> CGEventFlags {
        guard let modifiers, !modifiers.isEmpty else { return [] }

        var flags: CGEventFlags = []
        let parts = modifiers.lowercased().split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "alt", "option", "opt":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "fn", "function":
                flags.insert(.maskSecondaryFn)
            default:
                break
            }
        }

        return flags
    }

    // MARK: - Modifier Virtual Keys

    /// Returns virtual key codes for modifier flags so we can send discrete
    /// modifier key-down/key-up events (required by some apps).
    private func modifierVirtualKeys(_ flags: CGEventFlags) -> [CGKeyCode] {
        var keys: [CGKeyCode] = []
        if flags.contains(.maskCommand)   { keys.append(0x37) } // Left Command
        if flags.contains(.maskShift)     { keys.append(0x38) } // Left Shift
        if flags.contains(.maskAlternate) { keys.append(0x3A) } // Left Option
        if flags.contains(.maskControl)   { keys.append(0x3B) } // Left Control
        return keys
    }

    // MARK: - Virtual Key Codes

    private func virtualKeyCode(for key: String) -> CGKeyCode? {
        // Single character keys
        if key.count == 1, let char = key.first {
            return charToKeyCode(char)
        }

        // Named keys
        switch key {
        // Navigation
        case "return", "enter":       return 0x24
        case "tab":                   return 0x30
        case "space":                 return 0x31
        case "delete", "backspace":   return 0x33
        case "forwarddelete":         return 0x75
        case "escape", "esc":         return 0x35

        // Arrow keys
        case "up":                    return 0x7E
        case "down":                  return 0x7D
        case "left":                  return 0x7B
        case "right":                 return 0x7C

        // Page navigation
        case "home":                  return 0x73
        case "end":                   return 0x77
        case "pageup":               return 0x74
        case "pagedown":             return 0x79

        // Function keys
        case "f1":  return 0x7A
        case "f2":  return 0x78
        case "f3":  return 0x63
        case "f4":  return 0x76
        case "f5":  return 0x60
        case "f6":  return 0x61
        case "f7":  return 0x62
        case "f8":  return 0x64
        case "f9":  return 0x65
        case "f10": return 0x6D
        case "f11": return 0x67
        case "f12": return 0x6F

        default:
            return nil
        }
    }

    private func charToKeyCode(_ char: Character) -> CGKeyCode? {
        switch char.lowercased().first {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "o": return 0x1F
        case "u": return 0x20
        case "[": return 0x21
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "'": return 0x27
        case "k": return 0x28
        case ";": return 0x29
        case "\\": return 0x2A
        case ",": return 0x2B
        case "/": return 0x2C
        case "n": return 0x2D
        case "m": return 0x2E
        case ".": return 0x2F
        case "`": return 0x32
        default:  return nil
        }
    }
}
