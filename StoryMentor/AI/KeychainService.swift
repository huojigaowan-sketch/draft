import Foundation
import Security

enum KeychainService {
    private static let service = "com.liuyicheng.StoryMentor.credentials"
    private static let deepSeekAccount = "deepseek-api-key"
    private static let siliconFlowAccount = "siliconflow-api-key"

    static func saveAPIKey(_ value: String) throws {
        try save(value, account: deepSeekAccount)
    }

    nonisolated static func saveSiliconFlowAPIKey(_ value: String) throws {
        try save(value, account: "siliconflow-api-key")
    }

    nonisolated private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let service = "com.liuyicheng.StoryMentor.credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            update.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    nonisolated static func readAPIKey() throws -> String? {
        try read(account: "deepseek-api-key")
    }

    nonisolated static func readSiliconFlowAPIKey() throws -> String? {
        try read(account: "siliconflow-api-key")
    }

    nonisolated static func readLegacyOpenAICompatibleAPIKey() throws -> String? {
        try read(account: "openai-compatible-api-key")
    }

    nonisolated private static func read(account: String) throws -> String? {
        let service = "com.liuyicheng.StoryMentor.credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    static func deleteAPIKey() throws {
        try delete(account: deepSeekAccount)
    }

    static func deleteSiliconFlowAPIKey() throws {
        try delete(account: siliconFlowAccount)
    }

    private static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "无法访问钥匙串：\(message)"
        case .invalidData:
            return "钥匙串中的 API Key 数据无法读取。"
        }
    }
}
