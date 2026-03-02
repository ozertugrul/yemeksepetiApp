import Foundation
import Security

/// JWT access-token'ı Keychain'de güvenli şekilde saklar.
enum KeychainHelper {

    private static let service = "com.ozertuu.yemeksepetiApp"
    private static let tokenKey = "auth_token"
    private static let userKey  = "auth_user"

    // MARK: - Token

    static func saveToken(_ token: String) {
        save(key: tokenKey, value: token)
    }

    static func loadToken() -> String? {
        load(key: tokenKey)
    }

    static func deleteToken() {
        delete(key: tokenKey)
    }

    // MARK: - User snapshot (JSON)

    static func saveUser(_ data: Data) {
        saveData(key: userKey, data: data)
    }

    static func loadUser() -> Data? {
        loadData(key: userKey)
    }

    static func deleteUser() {
        delete(key: userKey)
    }

    // MARK: - Clear all

    static func clearAll() {
        deleteToken()
        deleteUser()
    }

    // MARK: - Private helpers

    private static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(key: key, data: data)
    }

    private static func load(key: String) -> String? {
        guard let data = loadData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveData(key: String, data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        // Try update first
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func loadData(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
