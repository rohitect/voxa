import os.log

/// Unified logging for Voxa using Apple's os.log framework.
/// Usage: Log.audio.info("Recording started")
enum Log {
    static let audio = Logger(subsystem: "com.voxa.app", category: "audio")
    static let transcription = Logger(subsystem: "com.voxa.app", category: "transcription")
    static let cleanup = Logger(subsystem: "com.voxa.app", category: "cleanup")
    static let injection = Logger(subsystem: "com.voxa.app", category: "injection")
    static let hotkey = Logger(subsystem: "com.voxa.app", category: "hotkey")
    static let model = Logger(subsystem: "com.voxa.app", category: "model")
    static let permissions = Logger(subsystem: "com.voxa.app", category: "permissions")
    static let general = Logger(subsystem: "com.voxa.app", category: "general")
}
