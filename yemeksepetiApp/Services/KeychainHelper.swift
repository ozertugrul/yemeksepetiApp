import Foundation
import Security

enum KeychainHelper {
    nonisolated private static let service = "com.ozertuu.yemeksepetiApp"
    nonisolated private static let tokenKey = "auth_token"
    nonisolated private static let userKey = "auth_user"

    nonisolated static func saveToken(_ token: String) {
        save(key: tokenKey, value: token)
    }

    nonisolated static func loadToken() -> String? {
        load(key: tokenKey)
    }

    nonisolated static func deleteToken() {
        delete(key: tokenKey)
    }

    nonisolated static func saveUser(_ data: Data) {
        saveData(key: userKey, data: data)
    }

    nonisolated static func loadUser() -> Data? {
        loadData(key: userKey)
    }

    nonisolated static func deleteUser() {
        delete(key: userKey)
    }

    nonisolated static func clearAll() {
        deleteToken()
        deleteUser()
    }

    nonisolated private static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(key: key, data: data)
    }

    nonisolated private static func load(key: String) -> String? {
        guard let data = loadData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func saveData(key: String, data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]

        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    nonisolated private static func loadData(key: String) -> Data? {
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

    nonisolated private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
