import Foundation

/// Manages a list of chat conversations with the active selection.
/// Conversations persist to disk at ~/.voxa/conversations/.
@Observable
final class ConversationStore {
    /// All conversations, newest first.
    private(set) var conversations: [ChatSession] = []

    /// The currently active conversation.
    var activeConversation: ChatSession

    /// Directory where conversation JSON files are stored.
    private let storageDirectory: URL

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

    init() {
        let dir = Constants.dataDirectory.appendingPathComponent("conversations", isDirectory: true)
        self.storageDirectory = dir

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load saved conversations
        let loaded = Self.loadAll(from: dir, decoder: JSONDecoder.conversationDecoder)
            .sorted { $0.createdAt > $1.createdAt }

        if loaded.isEmpty {
            let initial = ChatSession()
            self.activeConversation = initial
            self.conversations = [initial]
        } else {
            self.conversations = loaded
            // Temporary init — overwritten below
            self.activeConversation = loaded[0]
        }

        // Restore the last active conversation if available
        if !loaded.isEmpty,
           let lastActiveId = UserDefaults.standard.string(forKey: "conversation.activeId"),
           let id = UUID(uuidString: lastActiveId),
           let match = conversations.first(where: { $0.id == id }) {
            self.activeConversation = match
        }
    }

    // MARK: - Public API

    /// Create a new conversation and make it active.
    @discardableResult
    func newConversation() -> ChatSession {
        let session = ChatSession()
        conversations.insert(session, at: 0)
        activeConversation = session
        save(session)
        persistActiveId()
        return session
    }

    /// Switch to an existing conversation.
    func select(_ session: ChatSession) {
        activeConversation = session
        persistActiveId()
    }

    /// Delete a conversation. If it's the active one, switch to another.
    func delete(_ session: ChatSession) {
        conversations.removeAll { $0.id == session.id }
        deleteFile(for: session)
        if activeConversation.id == session.id {
            if let first = conversations.first {
                activeConversation = first
            } else {
                newConversation()
            }
        }
        persistActiveId()
    }

    /// Delete all conversations and start fresh.
    func deleteAll() {
        for conv in conversations {
            deleteFile(for: conv)
        }
        conversations.removeAll()
        newConversation()
    }

    /// Save the current active conversation to disk. Call after mutations.
    func saveActive() {
        save(activeConversation)
    }

    /// Grouped conversations for display: Today, Yesterday, Previous 7 Days, Older.
    var groupedConversations: [(title: String, sessions: [ChatSession])] {
        let calendar = Calendar.current
        let now = Date()

        var today: [ChatSession] = []
        var yesterday: [ChatSession] = []
        var lastWeek: [ChatSession] = []
        var older: [ChatSession] = []

        for conv in conversations {
            if calendar.isDateInToday(conv.createdAt) {
                today.append(conv)
            } else if calendar.isDateInYesterday(conv.createdAt) {
                yesterday.append(conv)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      conv.createdAt > weekAgo {
                lastWeek.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [(title: String, sessions: [ChatSession])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !lastWeek.isEmpty { groups.append(("Previous 7 Days", lastWeek)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    // MARK: - Persistence

    private func save(_ session: ChatSession) {
        let url = fileURL(for: session)
        do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[ConversationStore] Failed to save session \(session.id): \(error)")
        }
    }

    private func deleteFile(for session: ChatSession) {
        let url = fileURL(for: session)
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL(for session: ChatSession) -> URL {
        storageDirectory.appendingPathComponent("\(session.id.uuidString).json")
    }

    private func persistActiveId() {
        UserDefaults.standard.set(activeConversation.id.uuidString, forKey: "conversation.activeId")
    }

    private static func loadAll(from directory: URL, decoder: JSONDecoder) -> [ChatSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { url -> ChatSession? in
            guard url.pathExtension == "json" else { return nil }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(ChatSession.self, from: data)
            } catch {
                print("[ConversationStore] Failed to load \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }
}

// MARK: - Decoder convenience

private extension JSONDecoder {
    static let conversationDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
