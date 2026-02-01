import Foundation
import Security

// MARK: - Keychain Errors

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

// MARK: - Keychain Service

/// Простая обёртка для работы с Keychain (сохранение/чтение токенов).
/// Токены хранятся безопасно, в отличие от UserDefaults.
final class KeychainService {

    private let service: String
    private let logger: AppLogging?

    init(
        service: String = Bundle.main.bundleIdentifier ?? "CleanFeedVK",
        logger: AppLogging? = AppLogger.shared
    ) {
        self.service = service
        self.logger = logger
    }

    // MARK: - Сохранение

    /// Сохраняет строку (токен) в Keychain под указанным ключом.
    func save(value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Удаляем старое значение, если есть (иначе добавление вернёт errSecDuplicateItem)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Добавляем новое
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger?.error("Keychain", "save failed for key=\(key)", error: KeychainError.saveFailed(status))
            throw KeychainError.saveFailed(status)
        }

        logger?.info("Keychain", "saved key=\(key)")
    }

    // MARK: - Чтение

    /// Читает строку (токен) из Keychain по ключу.
    func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            logger?.debug("Keychain", "key=\(key) not found")
            return nil
        }

        guard status == errSecSuccess else {
            logger?.error("Keychain", "read failed for key=\(key)", error: KeychainError.readFailed(status))
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }

        logger?.debug("Keychain", "read key=\(key)")
        return value
    }

    // MARK: - Удаление

    /// Удаляет значение из Keychain.
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger?.error("Keychain", "delete failed for key=\(key)", error: KeychainError.deleteFailed(status))
            throw KeychainError.deleteFailed(status)
        }

        logger?.info("Keychain", "deleted key=\(key)")
    }
}
