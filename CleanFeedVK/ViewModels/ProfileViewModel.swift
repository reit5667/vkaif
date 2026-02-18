import Foundation
import Combine

/// Composition: Header (users.get) и вкладки (friends.get, groups.get, photos.getAlbums) загружаются асинхронно и независимо.
/// Один вызов на секцию (защита от дублей), refresh — явный forceRefresh.
@MainActor
final class ProfileViewModel: ObservableObject {

    private let authService: AuthService
    private let vkApi = VKApiService()

    /// nil = свой профиль, иначе ID друга.
    let userId: Int?

    // MARK: - Header (users.get + главное фото из альбома -6)

    @Published private(set) var user: VKUserDetail?
    @Published private(set) var userLoadState: ProfileLoadState = .idle
    /// Главное фото профиля из photos.get(album_id=-6) — полный размер; без него показываем fallback из users.get.
    @Published private(set) var profileMainPhoto: VKPhoto?

    // MARK: - Вкладки (отдельные вызовы, не одним await)

    @Published private(set) var friends: [VKFriend] = []
    @Published private(set) var friendsLoadState: ProfileTabLoadState = .idle

    @Published private(set) var groups: [VKGroup] = []
    @Published private(set) var groupsLoadState: ProfileTabLoadState = .idle

    @Published private(set) var albums: [VKAlbum] = []
    @Published private(set) var albumsLoadState: ProfileTabLoadState = .idle

    @Published private(set) var wallPosts: [VKPost] = []
    @Published private(set) var wallProfiles: [VKProfile] = []
    @Published private(set) var wallGroups: [VKGroup] = []
    @Published private(set) var wallLoadState: ProfileTabLoadState = .idle

    /// Защита от двойного onAppear: начальную загрузку запускаем только один раз.
    private var hasStartedInitialLoad = false

    init(authService: AuthService, userId: Int? = nil) {
        self.authService = authService
        self.userId = userId
    }

    /// Вызвать при появлении экрана профиля. Сначала header (users.get), затем параллельно вкладки — один раз за сессию экрана.
    func loadProfileIfNeeded() {
        guard authService.accessToken != nil else {
            userLoadState = .notAuthenticated
            return
        }
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true
        Task {
            await loadUserOnce(ids: userId.map { [String(describing: $0)] })
            let ownerIdForAlbums = user?.id ?? userId
            if let oid = user?.id ?? userId {
                Task { await loadProfileMainPhoto(ownerId: oid) }
                Task { await loadWall(ownerId: oid, forceRefresh: false) }
            }
            Task { await loadFriends(forceRefresh: false) }
            if userId == nil { Task { await loadGroups(forceRefresh: false) } }
            if let oid = ownerIdForAlbums { Task { await loadAlbums(ownerId: oid, forceRefresh: false) } }
        }
    }

    /// Обновить всё: header + вкладки независимо (кнопка «Обновить»).
    func refreshAll() {
        guard authService.accessToken != nil else { return }
        hasStartedInitialLoad = true
        profileMainPhoto = nil
        Task {
            await loadUserOnce(ids: userId.map { [String(describing: $0)] }, forceRefresh: true)
            let ownerIdForAlbums = user?.id ?? userId
            if let oid = user?.id ?? userId {
                Task { await loadProfileMainPhoto(ownerId: oid) }
                Task { await loadWall(ownerId: oid, forceRefresh: true) }
            }
            Task { await loadFriends(forceRefresh: true) }
            if userId == nil { Task { await loadGroups(forceRefresh: true) } }
            if let oid = ownerIdForAlbums { Task { await loadAlbums(ownerId: oid, forceRefresh: true) } }
        }
    }

    /// Один вызов users.get; при forceRefresh перезаписывает user.
    private func loadUserOnce(ids: [String]?, forceRefresh: Bool = false) async {
        if !forceRefresh, case .loading = userLoadState { return }
        if !forceRefresh, case .loaded = userLoadState, user != nil { return }
        guard let token = authService.accessToken else {
            await MainActor.run { userLoadState = .notAuthenticated }
            return
        }
        await MainActor.run { userLoadState = .loading }
        do {
            let users = try await vkApi.getUsers(token: token, userIds: ids)
            await MainActor.run {
                user = users.first
                userLoadState = .loaded
            }
        } catch {
            await MainActor.run { userLoadState = .failed(error) }
        }
    }

    /// Главное фото профиля (photos.get, album_id=-6) — полный размер для шапки и fullscreen.
    private func loadProfileMainPhoto(ownerId: Int) async {
        guard let token = authService.accessToken else { return }
        do {
            let photo = try await vkApi.getProfileMainPhoto(token: token, ownerId: ownerId)
            await MainActor.run { profileMainPhoto = photo }
        } catch {
            await MainActor.run { profileMainPhoto = nil }
        }
    }

    /// Загрузка всех друзей одним запросом (count=5000 — лимит VK API).
    func loadFriends(forceRefresh: Bool) async {
        if !forceRefresh, case .loading = friendsLoadState { return }
        if !forceRefresh, case .loaded = friendsLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { friendsLoadState = .loading }
        do {
            let response = try await vkApi.getFriends(token: token, userId: userId, count: 5000, offset: 0)
            await MainActor.run {
                friends = response.items
                friendsLoadState = .loaded
            }
        } catch {
            await MainActor.run { friendsLoadState = .failed(error) }
        }
    }

    /// Загрузка всех групп: цикл по offset до пустого ответа (VK при extended=1 часто отдаёт по 20–22 за раз; response.count не надёжен).
    func loadGroups(forceRefresh: Bool) async {
        if !forceRefresh, case .loading = groupsLoadState { return }
        if !forceRefresh, case .loaded = groupsLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { groupsLoadState = .loading }
        do {
            var allItems: [VKGroup] = []
            var offset = 0
            let pageSize = 1000
            while true {
                let response = try await vkApi.getGroups(token: token, count: pageSize, offset: offset)
                allItems.append(contentsOf: response.items)
                if response.items.isEmpty { break }
                offset = allItems.count
            }
            await MainActor.run {
                groups = allItems
                groupsLoadState = .loaded
            }
        } catch {
            await MainActor.run { groupsLoadState = .failed(error) }
        }
    }

    /// Удалить пост со стены (после успешного wall.delete). Убирает запись из wallPosts.
    func removeWallPost(_ post: VKPost) {
        wallPosts.removeAll { $0.postId == post.postId }
    }

    /// Стена пользователя (wall.get). ownerId — id пользователя (положительный).
    func loadWall(ownerId: Int?, forceRefresh: Bool) async {
        guard let ownerId = ownerId else { return }
        if !forceRefresh, case .loading = wallLoadState { return }
        if !forceRefresh, case .loaded = wallLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { wallLoadState = .loading }
        do {
            let response = try await vkApi.getWall(token: token, ownerId: ownerId, count: 30, offset: 0)
            await MainActor.run {
                wallPosts = response.items
                wallProfiles = response.profiles ?? []
                wallGroups = response.groups ?? []
                wallLoadState = .loaded
            }
        } catch {
            await MainActor.run { wallLoadState = .failed(error) }
        }
    }

    /// ownerId — явно переданный ID (свой или друга); без него альбомы не запрашиваем.
    func loadAlbums(ownerId: Int?, forceRefresh: Bool) async {
        guard let ownerId = ownerId else { return }
        if !forceRefresh, case .loading = albumsLoadState { return }
        if !forceRefresh, case .loaded = albumsLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { albumsLoadState = .loading }
        do {
            let response = try await vkApi.getPhotosAlbums(token: token, ownerId: ownerId)
            await MainActor.run {
                albums = response.items
                albumsLoadState = .loaded
            }
        } catch {
            await MainActor.run { albumsLoadState = .failed(error) }
        }
    }
}
