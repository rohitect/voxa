import AppKit
import Carbon

/// Injects text into the currently focused app by temporarily placing it on the pasteboard
/// and simulating Cmd+V. Saves and restores the original pasteboard contents.
final class TextInjector {

    /// Injects the given text into the frontmost app's focused text field.
    /// - Parameter text: The text to inject.
    static func inject(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current pasteboard contents
        let savedItems = savePasteboard(pasteboard)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        usleep(50_000) // 50ms

        // Simulate Cmd+V
        simulatePaste()

        // Restore original pasteboard after a delay (give the paste time to complete)
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.pasteboardRestoreDelay) {
            restorePasteboard(pasteboard, items: savedItems)
        }

        print("[TextInjector] Injected \(text.count) characters")
    }

    // MARK: - Pasteboard Save/Restore

    private struct PasteboardItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [PasteboardItem] {
        var items: [PasteboardItem] = []
        guard let types = pasteboard.types else { return items }
        for type in types {
            if let data = pasteboard.data(forType: type) {
                items.append(PasteboardItem(type: type, data: data))
            }
        }
        return items
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [PasteboardItem]) {
        pasteboard.clearContents()
        if items.isEmpty { return }
        for item in items {
            pasteboard.setData(item.data, forType: item.type)
        }
        print("[TextInjector] Pasteboard restored")
    }

    // MARK: - Simulate Paste (Cmd+V)

    private static func simulatePaste() {
        let vKeyCode = UInt16(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            print("[TextInjector] Failed to create CGEvent for paste")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
