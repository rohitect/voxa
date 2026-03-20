import Foundation

/// Extracts salient facts from a completed chat session via LLM.
final class MemoryExtractor {
    private let providerManager: LLMProviderManager

    init(providerManager: LLMProviderManager) {
        self.providerManager = providerManager
    }

    /// Extract memory candidates from a completed session.
    /// Returns empty array if no provider is available or session is trivial.
    func extract(session: ChatSession) async -> [MemoryCandidate] {
        // Skip trivial sessions (< 2 user messages)
        let userMessages = session.messages.filter { $0.role == .user }
        guard userMessages.count >= 2 else { return [] }

        guard let provider = providerManager.activeProvider else { return [] }

        // Build a transcript of user messages only (we care about what the user revealed)
        let transcript = userMessages.compactMap { $0.content }.joined(separator: "\n")
        guard !transcript.isEmpty else { return [] }

        let extractionPrompt = """
        Analyze the following conversation messages from a user and extract any personal facts, \
        preferences, corrections, or context worth remembering for future conversations.

        For each extracted fact, output a JSON array of objects with:
        - "type": one of "preference", "fact", "routine", "person", "project", "correction"
        - "content": the fact in a clear, standalone sentence
        - "importance": 1-10 (10 = critical personal info, 1 = trivial)

        Only extract genuinely useful facts. Skip generic requests ("open Safari", "what time is it"). \
        Focus on: names, roles, preferences, tools they use, people they mention, projects, corrections \
        to your behavior, and recurring patterns.

        If nothing worth extracting, return an empty array: []

        User messages:
        \(transcript)

        Respond ONLY with the JSON array, no other text.
        """

        do {
            let messages = [
                ChatMessage(role: .system, content: "You are a memory extraction assistant. Output only valid JSON."),
                ChatMessage(role: .user, content: extractionPrompt)
            ]

            let response = try await provider.chat(
                messages: messages,
                model: providerManager.activeModel,
                tools: nil,
                timeout: 15
            )

            guard let content = response.message.content else { return [] }
            return parseExtractionResponse(content)
        } catch {
            print("[MemoryExtractor] Extraction failed: \(error)")
            return []
        }
    }

    private func parseExtractionResponse(_ response: String) -> [MemoryCandidate] {
        // Find JSON array in the response (handle markdown code blocks)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: "\n")
            let stripped = lines.dropFirst().dropLast().joined(separator: "\n")
            jsonString = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct ExtractionItem: Decodable {
            let type: String
            let content: String
            let importance: Int?
        }

        do {
            let items = try JSONDecoder().decode([ExtractionItem].self, from: data)
            return items.compactMap { item in
                guard let type = MemoryEntry.MemoryType(rawValue: item.type) else { return nil }
                return MemoryCandidate(
                    type: type,
                    content: item.content,
                    importance: min(max(item.importance ?? 5, 1), 10)
                )
            }
        } catch {
            print("[MemoryExtractor] Failed to parse extraction response: \(error)")
            return []
        }
    }
}
