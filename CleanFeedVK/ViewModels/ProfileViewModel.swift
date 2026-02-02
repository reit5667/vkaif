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

    // MARK: - Header (users.get)

    @Published private(set) var user: VKUserDetail?
    @Published private(set) var userLoadState: ProfileLoadState = .idle

    // MARK: - Вкладки (отдельные вызовы, не одним await)

    @Published private(set) var friends: [VKFriend] = []
    @Published private(set) var friendsLoadState: ProfileTabLoadState = .idle

    @Published private(set) var groups: [VKGroup] = []
    @Published private(set) var groupsLoadState: ProfileTabLoadState = .idle

    @Published private(set) var albums: [VKAlbum] = []
    @Published private(set) var albumsLoadState: ProfileTabLoadState = .idle

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
            await MainActor.run {
                Task { await loadFriends(forceRefresh: false) }
                if userId == nil { Task { await loadGroups(forceRefresh: false) } }
                Task { await loadAlbums(forceRefresh: false) }
            }
        }
    }

    /// Обновить всё: header + вкладки независимо (кнопка «Обновить»).
    func refreshAll() {
        guard authService.accessToken != nil else { return }
        hasStartedInitialLoad = true
        Task {
            await loadUserOnce(ids: userId.map { [String(describing: $0)] }, forceRefresh: true)
            await MainActor.run {
                Task { await loadFriends(forceRefresh: true) }
                if userId == nil { Task { await loadGroups(forceRefresh: true) } }
                Task { await loadAlbums(forceRefresh: true) }
            }
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

    func loadFriends(forceRefresh: Bool) async {
        if !forceRefresh, case .loading = friendsLoadState { return }
        if !forceRefresh, case .loaded = friendsLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { friendsLoadState = .loading }
        do {
            let response = try await vkApi.getFriends(token: token, userId: userId)
            await MainActor.run {
                friends = response.items
                friendsLoadState = .loaded
            }
        } catch {
            await MainActor.run { friendsLoadState = .failed(error) }
        }
    }

    func loadGroups(forceRefresh: Bool) async {
        if !forceRefresh, case .loading = groupsLoadState { return }
        if !forceRefresh, case .loaded = groupsLoadState { return }
        guard let token = authService.accessToken else { return }
        await MainActor.run { groupsLoadState = .loading }
        do {
            let response = try await vkApi.getGroups(token: token)
            await MainActor.run {
                groups = response.items
                groupsLoadState = .loaded
            }
        } catch {
            await MainActor.run { groupsLoadState = .failed(error) }
        }
    }

    func loadAlbums(forceRefresh: Bool) async {
        if !forceRefresh, case .loading = albumsLoadState { return }
        if !forceRefresh, case .loaded = albumsLoadState { return }
        guard let token = authService.accessToken else { return }
        guard let ownerId = user?.id ?? userId else { return }
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
