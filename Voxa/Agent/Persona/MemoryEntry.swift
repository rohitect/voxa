import Foundation

/// A single extracted memory from a conversation.
struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    let type: MemoryType
    let content: String
    let source: String  // e.g. "session:2026-03-19T10:30:00Z"
    let createdAt: Date
    var importance: Int  // 1-10, LLM-assigned
    var lastAccessed: Date

    init(type: MemoryType, content: String, source: String, importance: Int = 5) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.source = source
        self.createdAt = Date()
        self.importance = importance
        self.lastAccessed = Date()
    }

    enum MemoryType: String, Codable, CaseIterable {
        case preference    // "prefers dark mode", "likes concise responses"
        case fact          // "uses MacBook Pro M3", "name is Rohit"
        case routine       // "does morning planning at 9am"
        case person        // "John is his manager"
        case project       // "working on Voxa app"
        case correction    // "don't call me sir"
    }
}

/// A candidate extracted from a session, before deduplication.
struct MemoryCandidate {
    let type: MemoryEntry.MemoryType
    let content: String
    let importance: Int
}
