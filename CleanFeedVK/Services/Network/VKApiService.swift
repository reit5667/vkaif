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

    // MARK: - users.get

    /// Загружает профили пользователей. Без userIds — текущий пользователь.
    /// - Parameters:
    ///   - token: access_token.
    ///   - userIds: ID или screen_name; nil/пусто = текущий пользователь.
    ///   - fields: доп. поля (photo_200, status и т.д.).
    func getUsers(
        token: String,
        userIds: [String]? = nil,
        fields: String = "photo_200,status"
    ) async throws -> [VKUserDetail] {
        guard !token.isEmpty else {
            logger?.error("VKApi", "getUsers: empty token")
            throw VKApiError.missingToken
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "fields", value: fields)
        ]
        if let ids = userIds, !ids.isEmpty {
            queryItems.append(URLQueryItem(name: "user_ids", value: ids.joined(separator: ",")))
        }

        guard var components = URLComponents(string: "\(baseURL)/users.get") else {
            throw VKApiError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw VKApiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        logger?.info("VKApi", "users.get userIds=\(userIds?.joined(separator: ",") ?? "current")")

        let wrapper: VKResponse<[VKUserDetail]>
        do {
            wrapper = try await network.request(VKResponse<[VKUserDetail]>.self, from: request)
        } catch {
            logger?.error("VKApi", "users.get failed", error: error)
            throw error
        }

        logger?.info("VKApi", "users.get ok, count=\(wrapper.response.count)")
        return wrapper.response
    }

    // MARK: - photos.getAlbums

    /// Альбомы пользователя (ownerId = nil — текущий).
    func getPhotosAlbums(
        token: String,
        ownerId: Int? = nil,
        count: Int = 50,
        offset: Int = 0
    ) async throws -> PhotosGetAlbumsResponse {
        guard !token.isEmpty else { throw VKApiError.missingToken }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let oid = ownerId { queryItems.append(URLQueryItem(name: "owner_id", value: String(oid))) }
        guard var components = URLComponents(string: "\(baseURL)/photos.getAlbums") else { throw VKApiError.invalidURL }
        components.queryItems = queryItems
        guard let url = components.url else { throw VKApiError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let wrapper: VKResponse<PhotosGetAlbumsResponse> = try await network.request(VKResponse<PhotosGetAlbumsResponse>.self, from: request)
        return wrapper.response
    }

    // MARK: - photos.get

    /// Фото альбома. album_id: числовой или -15 для «Сохранённые».
    func getPhotos(
        token: String,
        ownerId: Int,
        albumId: Int,
        count: Int = 50,
        offset: Int = 0
    ) async throws -> PhotosGetResponse {
        guard !token.isEmpty else { throw VKApiError.missingToken }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "owner_id", value: String(ownerId)),
            URLQueryItem(name: "album_id", value: String(albumId)),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "extended", value: "0")
        ]
        guard var components = URLComponents(string: "\(baseURL)/photos.get") else { throw VKApiError.invalidURL }
        components.queryItems = queryItems
        guard let url = components.url else { throw VKApiError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let wrapper: VKResponse<PhotosGetResponse> = try await network.request(VKResponse<PhotosGetResponse>.self, from: request)
        return wrapper.response
    }

    // MARK: - friends.get

    /// Список друзей (userId = nil — текущий).
    func getFriends(
        token: String,
        userId: Int? = nil,
        count: Int = 50,
        offset: Int = 0,
        fields: String = "photo_50"
    ) async throws -> FriendsGetResponse {
        guard !token.isEmpty else { throw VKApiError.missingToken }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "order", value: "name"),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "fields", value: fields)
        ]
        if let uid = userId { queryItems.append(URLQueryItem(name: "user_id", value: String(uid))) }
        guard var components = URLComponents(string: "\(baseURL)/friends.get") else { throw VKApiError.invalidURL }
        components.queryItems = queryItems
        guard let url = components.url else { throw VKApiError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let wrapper: VKResponse<FriendsGetResponse> = try await network.request(VKResponse<FriendsGetResponse>.self, from: request)
        return wrapper.response
    }

    // MARK: - groups.get

    /// Группы текущего пользователя.
    func getGroups(
        token: String,
        count: Int = 50,
        offset: Int = 0,
        extended: Int = 1
    ) async throws -> GroupsGetResponse {
        guard !token.isEmpty else { throw VKApiError.missingToken }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "extended", value: String(extended)),
            URLQueryItem(name: "filter", value: "groups"),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard var components = URLComponents(string: "\(baseURL)/groups.get") else { throw VKApiError.invalidURL }
        components.queryItems = queryItems
        guard let url = components.url else { throw VKApiError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let wrapper: VKResponse<GroupsGetResponse> = try await network.request(VKResponse<GroupsGetResponse>.self, from: request)
        return wrapper.response
    }
}
