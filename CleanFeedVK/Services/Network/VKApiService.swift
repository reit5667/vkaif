import Foundation

// MARK: - VK API Errors

enum VKApiError: Error {
    case missingToken
    case invalidURL
    case apiError(code: Int, message: String?)
}

// MARK: - VK API Service

/// Обёртка над NetworkService: строит URL для методов VK API.
/// Токен передаётся в каждый вызов (удобно для вызова из MainActor).
final class VKApiService: Sendable {

    private let baseURL = "https://api.vk.com/method"
    private let apiVersion = "5.131"

    private let network: any NetworkServiceProtocol
    private let logger: (any AppLogging)?

    init(
        network: any NetworkServiceProtocol = NetworkService(),
        logger: (any AppLogging)? = AppLogger.shared
    ) {
        self.network = network
        self.logger = logger
    }

    // MARK: - newsfeed.get

    /// Загружает ленту (только посты: filters=post).
    /// - Parameters:
    ///   - token: access_token из AuthService.
    ///   - startFrom: курсор пагинации (nil = первая страница).
    func getNewsfeed(token: String, startFrom: String? = nil) async throws -> NewsfeedGetResponse {
        guard !token.isEmpty else {
            logger?.error("VKApi", "getNewsfeed: empty token")
            throw VKApiError.missingToken
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "filters", value: "post"),
            URLQueryItem(name: "count", value: "20")
        ]
        if let from = startFrom, !from.isEmpty {
            queryItems.append(URLQueryItem(name: "start_from", value: from))
        }

        guard var components = URLComponents(string: "\(baseURL)/newsfeed.get") else {
            throw VKApiError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw VKApiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        logger?.info("VKApi", "newsfeed.get startFrom=\(startFrom ?? "nil")")

        // VK может вернуть { "error": { "error_code": 5, "error_msg": "..." } } вместо response
        let wrapper: VKResponse<NewsfeedGetResponse>
        do {
            wrapper = try await network.request(VKResponse<NewsfeedGetResponse>.self, from: request)
        } catch {
            logger?.error("VKApi", "newsfeed.get failed", error: error)
            throw error
        }

        logger?.info("VKApi", "newsfeed.get ok, items=\(wrapper.response.items.count)")
        return wrapper.response
    }
}
