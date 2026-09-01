import Security
import Foundation

/// API 키는 Keychain에만 둔다(ADR-0003). 설정 파일·코드·테스트에 넣지 않는다.
enum APIKeyStore {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yulaeun.ollama-usage-menubar",
            kSecAttrAccount as String: "ollama-api-key",
        ]
    }

    static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yulaeun.ollama-usage-menubar",
            kSecAttrAccount as String: "ollama-api-key",
        ]
    }
}