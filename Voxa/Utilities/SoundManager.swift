import AppKit

/// Plays subtle audio feedback for recording start/stop events using system sounds.
final class SoundManager {
    static let shared = SoundManager()

    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "audioFeedbackEnabled")
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "audioFeedbackEnabled") as? Bool ?? true
    }

    func playStartSound() {
        guard isEnabled else { return }
        // "Tink" is a subtle, short system sound — good for recording start
        NSSound(named: "Tink")?.play()
    }

    func playStopSound() {
        guard isEnabled else { return }
        // "Pop" is a subtle system sound — good for recording stop
        NSSound(named: "Pop")?.play()
    }

    func playDoneSound() {
        guard isEnabled else { return }
        NSSound(named: "Purr")?.play()
    }
}
