import Foundation

/// Manages voice shortcuts: trigger phrases that expand to predefined text.
/// Stored as JSON at ~/.voxa/shortcuts.json
@Observable
final class ShortcutManager {
    static let shared = ShortcutManager()

    var shortcuts: [VoiceShortcut] = []

    private let fileURL: URL

    struct VoiceShortcut: Codable, Identifiable {
        var id: String { trigger }
        let trigger: String   // e.g., "insert disclaimer"
        let expansion: String // e.g., full boilerplate paragraph
    }

    private init() {
        let voxaDir = Constants.dataDirectory
        try? FileManager.default.createDirectory(at: voxaDir, withIntermediateDirectories: true)
        self.fileURL = voxaDir.appendingPathComponent("shortcuts.json")
        load()
    }

    // MARK: - Match

    /// Checks if the transcript matches any shortcut trigger phrase.
    /// Returns the expansion text if matched, nil otherwise.
    func matchShortcut(in transcript: String) -> String? {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for shortcut in shortcuts {
            if normalized == shortcut.trigger.lowercased() ||
               normalized.hasPrefix(shortcut.trigger.lowercased()) {
                print("[Shortcuts] Matched trigger: \"\(shortcut.trigger)\"")
                return shortcut.expansion
            }
        }
        return nil
    }

    // MARK: - CRUD

    func addShortcut(trigger: String, expansion: String) {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty, !trimmedExpansion.isEmpty else { return }

        // Remove existing with same trigger
        shortcuts.removeAll { $0.trigger.lowercased() == trimmedTrigger }
        shortcuts.append(VoiceShortcut(trigger: trimmedTrigger, expansion: trimmedExpansion))
        save()
    }

    func removeShortcut(trigger: String) {
        shortcuts.removeAll { $0.trigger.lowercased() == trigger.lowercased() }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Shortcuts] No shortcuts file found — starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            shortcuts = try JSONDecoder().decode([VoiceShortcut].self, from: data)
            print("[Shortcuts] Loaded \(shortcuts.count) shortcuts")
        } catch {
            print("[Shortcuts] Failed to load: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(shortcuts)
            try data.write(to: fileURL, options: .atomic)
            print("[Shortcuts] Saved \(shortcuts.count) shortcuts")
        } catch {
            print("[Shortcuts] Failed to save: \(error)")
        }
    }
}
