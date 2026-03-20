import Foundation

/// Reads and writes semantic memory entries to ~/.voxa/agent/memory/.
@Observable
final class SemanticMemoryStore {
    private(set) var entries: [MemoryEntry] = []
    private let storageURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(agentDirectory: URL) {
        self.storageURL = agentDirectory
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("entries.json")

        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    // MARK: - CRUD

    func add(_ entry: MemoryEntry) {
        // Check for duplicate content (simple string match)
        if entries.contains(where: { $0.content.lowercased() == entry.content.lowercased() }) {
            return
        }
        entries.append(entry)
        save()
    }

    func addCandidates(_ candidates: [MemoryCandidate], source: String) {
        for candidate in candidates {
            let entry = MemoryEntry(
                type: candidate.type,
                content: candidate.content,
                source: source,
                importance: candidate.importance
            )
            add(entry)
        }
    }

    func update(_ entry: MemoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func remove(_ entry: MemoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func removeMatching(topic: String) {
        let lower = topic.lowercased()
        entries.removeAll { $0.content.lowercased().contains(lower) }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Retrieval

    /// Retrieve memories relevant to the given context, scored by recency + importance.
    func retrieve(query: String, maxCount: Int = 10) -> [MemoryEntry] {
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))
        let now = Date()

        let scored: [(MemoryEntry, Double)] = entries.map { entry in
            // Recency: exponential decay over 30 days
            let daysSince = now.timeIntervalSince(entry.lastAccessed) / 86400
            let recency = exp(-daysSince / 30.0)

            // Importance: normalized to 0-1
            let importance = Double(entry.importance) / 10.0

            // Relevance: simple word overlap (no embedding needed for v1)
            let entryWords = Set(entry.content.lowercased().split(separator: " ").map(String.init))
            let overlap = Double(queryWords.intersection(entryWords).count)
            let relevance = queryWords.isEmpty ? 0.5 : min(overlap / Double(queryWords.count), 1.0)

            // Weighted score: α*recency + β*importance + γ*relevance
            let score = 0.3 * recency + 0.3 * importance + 0.4 * relevance
            return (entry, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(maxCount)
            .map { entry, _ in
                // Mark as accessed
                var updated = entry
                updated.lastAccessed = now
                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[idx] = updated
                }
                return updated
            }
    }

    /// Build a formatted string of all memories for the system prompt.
    func formattedMemories() -> String {
        guard !entries.isEmpty else { return "" }

        var sections: [String: [String]] = [:]
        for entry in entries {
            let key = entry.type.rawValue.capitalized
            sections[key, default: []].append("- \(entry.content)")
        }

        var result = "## What I Remember About You\n"
        for (section, items) in sections.sorted(by: { $0.key < $1.key }) {
            result += "\n### \(section)\n"
            result += items.joined(separator: "\n") + "\n"
        }
        return result
    }

    /// Build a formatted string of relevant memories for a given context.
    func relevantMemoriesFormatted(context: String, maxCount: Int = 8) -> String {
        let relevant = retrieve(query: context, maxCount: maxCount)
        guard !relevant.isEmpty else { return "" }

        return "## Relevant Memories\n" +
            relevant.map { "- [\($0.type.rawValue)] \($0.content)" }.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            entries = try decoder.decode([MemoryEntry].self, from: data)
        } catch {
            print("[SemanticMemoryStore] Failed to load: \(error)")
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SemanticMemoryStore] Failed to save: \(error)")
        }
    }
}
