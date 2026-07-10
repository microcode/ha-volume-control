import Foundation
import Security

enum KeychainHelper {
    private static let service = Bundle.main.bundleIdentifier ?? "HA-Volume-Control"

    static func save(_ value: String, forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// One-time migration: moves an existing token from UserDefaults to the Keychain
    /// and removes it from the plist.
    static func migrateTokenIfNeeded() {
        guard let token = UserDefaults.standard.string(forKey: "haToken"),
              !token.isEmpty,
              load(forKey: "haToken").isEmpty else { return }
        save(token, forKey: "haToken")
        UserDefaults.standard.removeObject(forKey: "haToken")
    }
}
