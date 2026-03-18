import Foundation

/// Stores API keys in a file within Application Support with restricted permissions.
/// This avoids login keychain password prompts that occur with unsigned/ad-hoc builds.
/// Keys are stored in ~/Library/Application Support/Voxa/keys.json (chmod 600).
enum KeychainHelper {
    private static var keysURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voxaDir = appSupport.appendingPathComponent("Voxa")
        return voxaDir.appendingPathComponent("keys.json")
    }

    /// Save a string value.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        var store = loadStore()
        store[key] = value
        return writeStore(store)
    }

    /// Load a string value.
    static func load(key: String) -> String? {
        let store = loadStore()
        return store[key]
    }

    /// Delete a value.
    @discardableResult
    static func delete(key: String) -> Bool {
        var store = loadStore()
        store.removeValue(forKey: key)
        return writeStore(store)
    }

    // MARK: - Private

    private static func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: keysURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeStore(_ store: [String: String]) -> Bool {
        let dir = keysURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(store) else { return false }

        do {
            try data.write(to: keysURL, options: .atomic)
            // Restrict permissions to owner only (chmod 600)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keysURL.path
            )
            return true
        } catch {
            print("[KeychainHelper] Failed to write keys: \(error)")
            return false
        }
    }
}
