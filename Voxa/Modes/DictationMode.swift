import Foundation

/// The available dictation modes.
enum DictationModeType: String, CaseIterable, Identifiable {
    case pushToTalk = "Push to Talk"
    case flow = "Flow"
    case command = "Command"
    case agent = "Agent"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .pushToTalk: return "Hold hotkey to record, release to process"
        case .flow: return "Toggle hotkey for hands-free continuous dictation"
        case .command: return "Highlight text, press hotkey, speak a command"
        case .agent: return "Voice-driven AI agent with tools and multi-turn chat"
        }
    }

    var icon: String {
        switch self {
        case .pushToTalk: return "hand.tap.fill"
        case .flow: return "waveform.path"
        case .command: return "text.cursor"
        case .agent: return "brain.head.profile"
        }
    }
}
