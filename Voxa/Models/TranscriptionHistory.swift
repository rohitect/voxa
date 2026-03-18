import Foundation

/// Tracks transcription history for display in the Home page.
@Observable
final class TranscriptionHistory {
    static let shared = TranscriptionHistory()

    struct Entry: Identifiable, Codable {
        let id: UUID
        let text: String
        let timestamp: Date
        let mode: String

        init(text: String, mode: String) {
            self.id = UUID()
            self.text = text
            self.timestamp = Date()
            self.mode = mode
        }
    }

    var entries: [Entry] = []

    /// Total words transcribed (all time)
    var totalWords: Int {
        entries.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    /// Entries grouped by date label ("Today", "Yesterday", or formatted date)
    var groupedEntries: [(label: String, entries: [Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> String in
            if calendar.isDateInToday(entry.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(entry.timestamp) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: entry.timestamp)
            }
        }
        // Sort groups: Today first, then Yesterday, then by date descending
        let order = ["Today", "Yesterday"]
        return grouped.sorted { a, b in
            let aIdx = order.firstIndex(of: a.key) ?? Int.max
            let bIdx = order.firstIndex(of: b.key) ?? Int.max
            if aIdx != bIdx { return aIdx < bIdx }
            return (a.value.first?.timestamp ?? .distantPast) > (b.value.first?.timestamp ?? .distantPast)
        }
        .map { (label: $0.key, entries: $0.value.sorted { $0.timestamp > $1.timestamp }) }
    }

    private let fileURL: URL

    private init() {
        let voxaDir = Constants.dataDirectory
        try? FileManager.default.createDirectory(at: voxaDir, withIntermediateDirectories: true)
        self.fileURL = voxaDir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, mode: String) {
        let entry = Entry(text: text, mode: mode)
        entries.insert(entry, at: 0)
        // Keep last 500 entries
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            print("[History] Failed to load: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[History] Failed to save: \(error)")
        }
    }
}
