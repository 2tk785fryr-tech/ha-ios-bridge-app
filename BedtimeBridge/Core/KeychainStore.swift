import Foundation
import Security

/// API keys and the Home Assistant token live in the Keychain, not UserDefaults, so they
/// aren't in plain-text backups.
enum KeychainStore {
    private static let service = "BedtimeBridge.apiKeys"
    static let homeAssistantAccount = "homeAssistant"

    static func apiKey(for source: DriveTimeSource) -> String { secret(source.rawValue) }

    static func setAPIKey(_ key: String, for source: DriveTimeSource) { setSecret(key, account: source.rawValue) }

    static func secret(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func setSecret(_ value: String, account: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(match as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = match
        item[kSecValueData as String] = Data(trimmed.utf8)
        // Shortcuts and the alarm buttons may run while the phone is locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
