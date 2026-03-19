import Foundation

/// Classifies user intent from transcribed voice input.
enum Intent: Sendable {
    case agentChat
    case systemControl(SystemControlAction)

    enum SystemControlAction: Sendable {
        case stop
        case cancel
        case reset
        case newSession
    }
}

struct IntentClassifier {

    /// Classify a transcript into an intent.
    /// System control commands are matched by exact keyword.
    /// Everything else goes to the LLM as agent chat — the LLM decides
    /// whether to use tools, rewrite text, or just respond.
    static func classify(_ transcript: String) -> Intent {
        let lower = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let action = systemControlAction(lower) {
            return .systemControl(action)
        }

        return .agentChat
    }

    // MARK: - System Control

    private static let systemControlKeywords: [String: Intent.SystemControlAction] = [
        "stop": .stop,
        "cancel": .cancel,
        "nevermind": .cancel,
        "never mind": .cancel,
        "reset": .reset,
        "clear": .reset,
        "start over": .reset,
        "new session": .newSession,
        "new chat": .newSession,
    ]

    private static func systemControlAction(_ lower: String) -> Intent.SystemControlAction? {
        systemControlKeywords[lower]
    }
}
