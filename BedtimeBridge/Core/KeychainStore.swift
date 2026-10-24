import Foundation
import Security

/// API keys live in the Keychain, not UserDefaults, so they aren't in plain-text backups.
enum KeychainStore {
    private static let service = "BedtimeBridge.apiKeys"

    static func apiKey(for source: DriveTimeSource) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: source.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func setAPIKey(_ key: String, for source: DriveTimeSource) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: source.rawValue,
        ]
        SecItemDelete(match as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = match
        item[kSecValueData as String] = Data(trimmed.utf8)
        // Shortcuts may run the bedtime action while the phone is locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
