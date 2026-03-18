import Foundation

/// Classifies user intent from transcribed voice input.
/// Tier 1: Fast regex/keyword matching.
/// Tier 2: LLM fallback for ambiguous input.
enum Intent: Sendable {
    case dictation
    case textRewrite(text: String, command: String)
    case toolInvocation
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

    // MARK: - Tier 1: Fast keyword/regex matching

    static func classify(_ transcript: String) -> Intent {
        let lower = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // System control commands
        if isSystemControl(lower) {
            return systemControlIntent(lower)
        }

        // Direct tool invocation patterns
        if isToolInvocation(lower) {
            return .toolInvocation
        }

        // Default: treat as agent chat (LLM decides what to do)
        return .agentChat
    }

    // MARK: - System Control

    private static func isSystemControl(_ lower: String) -> Bool {
        let exact = ["stop", "cancel", "reset", "new session", "new chat", "clear", "start over", "nevermind", "never mind"]
        return exact.contains(lower)
    }

    private static func systemControlIntent(_ lower: String) -> Intent {
        switch lower {
        case "stop", "cancel", "nevermind", "never mind":
            return .systemControl(.cancel)
        case "reset", "clear", "start over":
            return .systemControl(.reset)
        case "new session", "new chat":
            return .systemControl(.newSession)
        default:
            return .systemControl(.stop)
        }
    }

    // MARK: - Tool Invocation Patterns

    private static let toolPatterns: [(pattern: String, tool: String)] = [
        (#"^open\s+.+"#, "app_launcher"),
        (#"^launch\s+.+"#, "app_launcher"),
        (#"^switch\s+to\s+.+"#, "app_launcher"),
        (#"^quit\s+.+"#, "app_launcher"),
        (#"^close\s+.+"#, "app_launcher"),
        (#"^(go\s+to|open)\s+.*settings"#, "system_settings"),
        (#"^copy\s+"#, "clipboard"),
        (#"^paste"#, "clipboard"),
        (#"^(what'?s\s+on\s+(the\s+)?clipboard|read\s+clipboard)"#, "clipboard"),
        (#"^(find|search\s+for)\s+(file|files)\s+"#, "file_search"),
        (#"^(take\s+a\s+)?screenshot"#, "screen_capture"),
        (#"^(capture|read)\s+(the\s+)?screen"#, "screen_capture"),
        (#"^what'?s\s+on\s+(the\s+|my\s+)?screen"#, "screen_capture"),
        (#"^(click|type|press)\s+"#, "ui_automation"),
        (#"^run\s+(the\s+)?(command|script)\s+"#, "shell_command"),
    ]

    private static func isToolInvocation(_ lower: String) -> Bool {
        for (pattern, _) in toolPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
