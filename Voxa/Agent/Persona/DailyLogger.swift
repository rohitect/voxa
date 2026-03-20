import Foundation

/// Append-only daily log writer for episodic memory.
/// Each day gets a single markdown file: logs/YYYY-MM-DD.md
final class DailyLogger {
    private let logsDirectory: URL

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(agentDirectory: URL) {
        self.logsDirectory = agentDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    /// Log a completed session summary.
    func logSession(title: String, userMessages: [String], assistantSummary: String, toolsUsed: [String]) {
        let time = timeFormatter.string(from: Date())
        var entry = "### \(time) — \(title)\n"

        if !userMessages.isEmpty {
            let firstMessage = userMessages.first ?? ""
            let preview = String(firstMessage.prefix(100))
            entry += "- **User:** \(preview)\n"
        }

        if !assistantSummary.isEmpty {
            let preview = String(assistantSummary.prefix(150))
            entry += "- **Assistant:** \(preview)\n"
        }

        if !toolsUsed.isEmpty {
            entry += "- **Tools:** \(toolsUsed.joined(separator: ", "))\n"
        }

        entry += "\n"
        appendToTodayLog(entry)
    }

    /// Load today's log content (for system prompt context).
    func todayLog() -> String {
        let filename = dateFormatter.string(from: Date()) + ".md"
        let url = logsDirectory.appendingPathComponent(filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Load yesterday's log content.
    func yesterdayLog() -> String {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return "" }
        let filename = dateFormatter.string(from: yesterday) + ".md"
        let url = logsDirectory.appendingPathComponent(filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func appendToTodayLog(_ entry: String) {
        let filename = dateFormatter.string(from: Date()) + ".md"
        let url = logsDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            let header = "# Voxa Daily Log — \(dateFormatter.string(from: Date()))\n\n"
            try? (header + entry).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
