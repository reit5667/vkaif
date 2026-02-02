import Foundation
import Combine

// MARK: - Auth Errors

enum AuthError: Error {
    case invalidAuthURL
    case tokenNotFound
    case userCancelled
    case keychainError(Error)
}

// MARK: - Auth State

enum AuthState {
    case idle           // Не начинали авторизацию
    case authenticating // В процессе (показан браузер)
    case authenticated  // Успешно, токен есть
    case failed(Error)  // Ошибка
}

// MARK: - Auth Service

/// Управляет OAuth 2.0 Implicit Flow для VK API.
/// - Строит URL авторизации (Kate Mobile App ID).
/// - Парсит токен из redirect URL.
/// - Сохраняет токен в Keychain.
@MainActor
final class AuthService: ObservableObject {

    // MARK: - Конфигурация VK OAuth

    private let appID = "2685278"              // Kate Mobile
    private let scope = "wall,offline"         // Разрешения: лента + бессрочный токен
    private let redirectURI = "https://oauth.vk.com/blank.html"
    private let display = "mobile"             // Мобильная версия страницы входа
    private let responseType = "token"         // Implicit Flow

    // MARK: - Зависимости

    private let keychain: KeychainService
    private let logger: AppLogging?

    private let tokenKey = "vk_access_token"

    // MARK: - Состояние (для UI)

    @Published private(set) var state: AuthState = .idle
    @Published private(set) var accessToken: String?

    // MARK: - Init

    init(
        keychain: KeychainService = KeychainService(logger: nil),
        logger: (any AppLogging)? = nil
    ) {
        self.keychain = keychain
        self.logger = logger ?? AppLogger.shared

        // При старте пытаемся загрузить токен из Keychain
        loadTokenFromKeychain()
    }

    // MARK: - Публичный API

    /// Возвращает URL для открытия в WKWebView.
    func buildAuthURL() -> URL? {
        var components = URLComponents(string: "https://oauth.vk.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "display", value: display),
            URLQueryItem(name: "response_type", value: responseType),
            URLQueryItem(name: "v", value: "5.131") // Версия API
        ]

        guard let url = components?.url else {
            logger?.error("Auth", "buildAuthURL failed")
            return nil
        }

        logger?.debug("Auth", "authURL: \(url.absoluteString)")
        return url
    }

    /// Начинает процесс авторизации (UI покажет браузер).
    func startAuthentication() {
        state = .authenticating
        logger?.info("Auth", "started authentication")
    }

    /// Обрабатывает redirect URL из WKWebView.
    /// Если URL содержит токен — сохраняет его, обновляет состояние.
    func handleRedirect(url: URL) {
        logger?.debug("Auth", "handleRedirect: \(url.absoluteString)")

        // Проверяем, что это наш redirect
        guard url.absoluteString.hasPrefix(redirectURI) else {
            return
        }

        // Парсим fragment (#access_token=...&expires_in=0&user_id=123)
        guard let fragment = url.fragment else {
            state = .failed(AuthError.tokenNotFound)
            logger?.error("Auth", "no fragment in redirect URL")
            return
        }

        let params = parseFragment(fragment)
        guard let token = params["access_token"], !token.isEmpty else {
            // Если токена нет — возможно, пользователь отменил вход (error=access_denied)
            if params["error"] == "access_denied" {
                state = .failed(AuthError.userCancelled)
                logger?.warning("Auth", "user cancelled")
            } else {
                state = .failed(AuthError.tokenNotFound)
                logger?.error("Auth", "access_token not found in fragment")
            }
            return
        }

        // Сохраняем токен в Keychain
        do {
            try keychain.save(value: token, for: tokenKey)
            accessToken = token
            state = .authenticated
            logger?.info("Auth", "authenticated successfully, token saved")
        } catch {
            state = .failed(AuthError.keychainError(error))
            logger?.error("Auth", "keychain save failed", error: error)
        }
    }

    /// Выход (удаляет токен из Keychain).
    func logout() {
        do {
            try keychain.delete(key: tokenKey)
            accessToken = nil
            state = .idle
            logger?.info("Auth", "logged out")
        } catch {
            logger?.error("Auth", "logout failed", error: error)
        }
    }

    // MARK: - Приватные

    private func loadTokenFromKeychain() {
        do {
            if let token = try keychain.read(key: tokenKey), !token.isEmpty {
                accessToken = token
                state = .authenticated
                logger?.info("Auth", "loaded token from keychain")
            } else {
                state = .idle
            }
        } catch {
            logger?.error("Auth", "loadTokenFromKeychain failed", error: error)
            state = .idle
        }
    }

    /// Парсит fragment вида "access_token=abc&expires_in=0&user_id=123"
    private func parseFragment(_ fragment: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = fragment.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                result[kv[0]] = kv[1]
            }
        }
        return result
    }
}
