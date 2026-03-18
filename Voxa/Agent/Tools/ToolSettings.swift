import Foundation

@Observable
final class ToolSettings {
    private let defaults = UserDefaults.standard
    private let keyPrefix = "agent.tool.enabled."

    /// Tools disabled by default.
    private let disabledByDefault: Set<String> = ["shell_command"]

    func isEnabled(_ toolName: String) -> Bool {
        let key = keyPrefix + toolName
        if defaults.object(forKey: key) == nil {
            return !disabledByDefault.contains(toolName)
        }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ toolName: String, enabled: Bool) {
        defaults.set(enabled, forKey: keyPrefix + toolName)
    }
}
