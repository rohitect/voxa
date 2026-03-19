import Foundation

/// Manages a list of chat conversations with the active selection.
/// Conversations persist in memory for the app session.
@Observable
final class ConversationStore {
    /// All conversations, newest first.
    private(set) var conversations: [ChatSession] = []

    /// The currently active conversation.
    var activeConversation: ChatSession

    init() {
        let initial = ChatSession()
        self.activeConversation = initial
        self.conversations = [initial]
    }

    /// Create a new conversation and make it active.
    @discardableResult
    func newConversation() -> ChatSession {
        let session = ChatSession()
        conversations.insert(session, at: 0)
        activeConversation = session
        return session
    }

    /// Switch to an existing conversation.
    func select(_ session: ChatSession) {
        activeConversation = session
    }

    /// Delete a conversation. If it's the active one, switch to another.
    func delete(_ session: ChatSession) {
        conversations.removeAll { $0.id == session.id }
        if activeConversation.id == session.id {
            if let first = conversations.first {
                activeConversation = first
            } else {
                // Create a fresh one if all deleted
                newConversation()
            }
        }
    }

    /// Delete all conversations and start fresh.
    func deleteAll() {
        conversations.removeAll()
        newConversation()
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
}
