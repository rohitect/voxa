import Foundation

/// Manages a personal dictionary that maps commonly misheard words to their correct spelling.
/// Stored as JSON at ~/.voxa/dictionary.json
@Observable
final class DictionaryManager {
    static let shared = DictionaryManager()

    var entries: [String: String] = [:] // misheard → correct

    private let fileURL: URL

    private init() {
        let voxaDir = Constants.dataDirectory
        try? FileManager.default.createDirectory(at: voxaDir, withIntermediateDirectories: true)
        self.fileURL = voxaDir.appendingPathComponent("dictionary.json")
        load()
    }

    // MARK: - Apply

    /// Applies dictionary replacements to the given text (case-insensitive word boundary matching).
    func apply(to text: String) -> String {
        guard !entries.isEmpty else { return text }

        var result = text
        for (misheard, correct) in entries {
            // Case-insensitive whole-word replacement
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: misheard))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: correct
                )
            }
        }

        if result != text {
            print("[Dictionary] Applied replacements: \"\(text)\" → \"\(result)\"")
        }
        return result
    }

    // MARK: - CRUD

    func addEntry(misheard: String, correct: String) {
        let key = misheard.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return }
        entries[key] = value
        save()
    }

    func removeEntry(misheard: String) {
        entries.removeValue(forKey: misheard.lowercased())
        save()
    }

    func updateEntry(misheard: String, correct: String) {
        addEntry(misheard: misheard, correct: correct)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Dictionary] No dictionary file found — starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([String: String].self, from: data)
            print("[Dictionary] Loaded \(entries.count) entries")
        } catch {
            print("[Dictionary] Failed to load: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
            print("[Dictionary] Saved \(entries.count) entries")
        } catch {
            print("[Dictionary] Failed to save: \(error)")
        }
    }
}
