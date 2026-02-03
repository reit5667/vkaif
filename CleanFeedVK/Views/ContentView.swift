import SwiftUI

/// Навигация из ленты: тап по автору поста → группа или профиль пользователя.
enum FeedDestination: Hashable {
    case group(id: Int)
    case user(id: Int)
}

struct ContentView: View {

    @StateObject private var authService: AuthService
    /// Один ViewModel для таба «Профиль» — не пересоздаётся при переключении табов, данные друзей/групп/альбомов сохраняются.
    @StateObject private var profileViewModel: ProfileViewModel
    @State private var showAuthView = false

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(authService: auth, userId: nil))
    }
    @State private var feedLoadState: FeedLoadState = .idle
    @State private var feedPosts: [VKPost] = []
    @State private var feedProfiles: [VKProfile] = []
    @State private var feedGroups: [VKGroup] = []
    @State private var nextFrom: String? = nil       // курсор для подгрузки
    @State private var isLoadingMore: Bool = false  // подгрузка в конец
    @State private var commentsContext: PostCommentsContext? = nil
    /// Переопределения счётчика лайков после likes.add (postId -> новый count).
    @State private var postLikeOverrides: [String: Int] = [:]
    /// Переопределения «лайкнуто» после likes.add (postId -> true).
    @State private var postLikedOverrides: [String: Bool] = [:]
    @State private var likeInProgress: Set<String> = []  // postId, чтобы не дублировать запросы

    private let vkApi = VKApiService()
    private let feedFilter = FeedFilter(blacklistKeywords: []) // позже — настройки

    var body: some View {
        NavigationView {
            Group {
                if case .authenticated = authService.state {
                    TabView {
                        NavigationStack {
                            feedTabContent
                        }
                        .tabItem { Label("Лента", systemImage: "list.bullet.rectangle") }
                        NavigationStack {
                            ProfileView(authService: authService, viewModel: profileViewModel)
                        }
                        .tabItem { Label("Профиль", systemImage: "person.circle") }
                    }
                } else {
                    mainContentStack
                }
            }
            .sheet(isPresented: $showAuthView) {
                AuthView(authService: authService)
            }
        }
    }

    private var feedTabContent: some View {
        Group {
            if !feedPosts.isEmpty {
                feedListView
            } else {
                mainContentStack
            }
        }
        .navigationTitle("Главная")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Обновить") { loadFeed() }
                    .disabled(feedLoadState.isLoading)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Выйти") {
                    authService.logout()
                    feedPosts = []
                    feedProfiles = []
                    feedGroups = []
                    nextFrom = nil
                    postLikeOverrides = [:]
                    postLikedOverrides = [:]
                }
            }
        }
    }

    // MARK: - Лента постов (LazyVStack)

    private var feedListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(feedPosts, id: \.postId) { post in
                    PostCellView(
                        post: post,
                        authorName: authorName(for: post),
                        authorAvatarURL: authorAvatarURL(for: post),
                        relativeDate: relativeDateString(from: post.date),
                        authService: authService,
                        feedDestination: feedDestination(for: post),
                        onTapComments: {
                            commentsContext = PostCommentsContext(
                                ownerId: post.ownerId ?? post.fromId ?? 0,
                                postId: post.id,
                                totalCount: post.commentsCount
                            )
                        },
                        likesCountOverride: postLikeOverrides[post.postId],
                        isLikedOverride: postLikedOverrides[post.postId],
                        onLike: likeInProgress.contains(post.postId) ? nil : { likeToggle(post) },
                        likeInProgress: likeInProgress.contains(post.postId)
                    )
                    .padding(.vertical, 8)
                    Divider()
                }

                // Триггер подгрузки при достижении конца
                if nextFrom != nil {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { loadMoreFeed() }
                }

                if isLoadingMore {
                    ProgressView("Ещё посты…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal)
        }
        .navigationDestination(for: FeedDestination.self) { dest in
            switch dest {
            case .group(let id):
                GroupWallView(authService: authService, groupId: id)
            case .user(let id):
                ProfileViewWrapper(authService: authService, userId: id)
            }
        }
        .sheet(item: $commentsContext) { ctx in
            PostCommentsView(context: ctx, authService: authService)
        }
        .overlay(alignment: .top) {
            if feedLoadState.isLoading {
                ProgressView("Загрузка…")
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
    }

    private var mainContentStack: some View {
        VStack(spacing: 20) {
            Text("CleanFeedVK")
                .font(.largeTitle)
                .fontWeight(.bold)
            Divider()
            statusSection
            actionButtons
            feedResultView
        }
        .padding()
    }

    private func authorName(for post: VKPost) -> String {
        CleanFeedVK.authorName(for: post, profiles: feedProfiles, groups: feedGroups)
    }

    private func authorAvatarURL(for post: VKPost) -> String? {
        CleanFeedVK.authorAvatarURL(for: post, profiles: feedProfiles, groups: feedGroups)
    }

    private func feedDestination(for post: VKPost) -> FeedDestination? {
        guard let id = post.ownerId ?? post.fromId else { return nil }
        if id < 0 {
            return .group(id: abs(id))
        } else {
            return .user(id: id)
        }
    }

    // MARK: - Views

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Статус авторизации:")
                .font(.headline)

            switch authService.state {
            case .idle:
                Label("Не авторизован", systemImage: "person.slash")
                    .foregroundColor(.secondary)
            case .authenticating:
                Label("Авторизация...", systemImage: "arrow.clockwise")
                    .foregroundColor(.blue)
            case .authenticated:
                Label("Авторизован ✓", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                if let token = authService.accessToken {
                    Text("Токен: \(String(token.prefix(20)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .failed(let error):
                Label("Ошибка: \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if case .authenticated = authService.state {
                Button(action: loadFeed) {
                    Label(
                        feedLoadState.isLoading ? "Загрузка…" : "Загрузить ленту",
                        systemImage: "list.bullet.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedLoadState.isLoading)

                Button(action: authService.logout) {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: {
                    authService.startAuthentication()
                    showAuthView = true
                }) {
                    Label("Войти через ВКонтакте", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var feedResultView: some View {
        switch feedLoadState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Загрузка ленты…")
        case .loaded(let count):
            Label("Загружено постов: \(count)", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let error):
            Label("Ошибка: \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }

    // MARK: - Загрузка ленты

    /// Первая загрузка или обновление (заменяет ленту).
    private func loadFeed() {
        guard let token = authService.accessToken else { return }
        feedLoadState = .loading
        Task {
            do {
                let response = try await vkApi.getNewsfeed(token: token)
                let filtered = feedFilter.filter(response.items)
                if response.items.count != filtered.count {
                    print("[CleanFeedVK] Фильтр: было \(response.items.count), осталось \(filtered.count)")
                }
                await MainActor.run {
                    feedPosts = filtered
                    feedProfiles = response.profiles ?? []
                    feedGroups = response.groups ?? []
                    nextFrom = response.nextFrom
                    feedLoadState = .loaded(count: filtered.count)
                }
                printFeedToConsole(posts: filtered, nextFrom: response.nextFrom)
            } catch {
                await MainActor.run {
                    feedLoadState = .failed(error)
                }
            }
        }
    }

    /// Подгрузка следующей страницы в конец ленты.
    private func loadMoreFeed() {
        guard let token = authService.accessToken,
              let from = nextFrom,
              !from.isEmpty,
              !feedLoadState.isLoading,
              !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            do {
                let response = try await vkApi.getNewsfeed(token: token, startFrom: from)
                let filtered = feedFilter.filter(response.items)
                await MainActor.run {
                    feedPosts.append(contentsOf: filtered)
                    mergeProfiles(response.profiles ?? [])
                    mergeGroups(response.groups ?? [])
                    nextFrom = response.nextFrom
                    isLoadingMore = false
                }
                if !filtered.isEmpty {
                    print("[CleanFeedVK] Подгружено ещё \(filtered.count) постов, next_from: \(response.nextFrom ?? "nil")")
                }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }

    private func mergeProfiles(_ new: [VKProfile]) {
        let existingIds = Set(feedProfiles.map(\.id))
        let toAdd = new.filter { !existingIds.contains($0.id) }
        if !toAdd.isEmpty { feedProfiles.append(contentsOf: toAdd) }
    }

    private func mergeGroups(_ new: [VKGroup]) {
        let existingIds = Set(feedGroups.map(\.id))
        let toAdd = new.filter { !existingIds.contains($0.id) }
        if !toAdd.isEmpty { feedGroups.append(contentsOf: toAdd) }
    }

    /// Toggle лайка поста: если уже лайкнут — likes.delete, иначе likes.add.
    private func likeToggle(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let pid = post.postId
        if likeInProgress.contains(pid) { return }
        let isLiked = postLikedOverrides[pid] ?? (post.likes?.userLikes == 1)
        likeInProgress.insert(pid)
        Task {
            do {
                let newCount: Int
                if isLiked {
                    newCount = try await vkApi.likesDelete(
                        token: token,
                        type: "post",
                        ownerId: ownerId,
                        itemId: post.id
                    )
                    await MainActor.run {
                        postLikeOverrides[pid] = newCount
                        postLikedOverrides[pid] = false
                        likeInProgress.remove(pid)
                    }
                } else {
                    newCount = try await vkApi.likesAdd(
                        token: token,
                        type: "post",
                        ownerId: ownerId,
                        itemId: post.id
                    )
                    await MainActor.run {
                        postLikeOverrides[pid] = newCount
                        postLikedOverrides[pid] = true
                        likeInProgress.remove(pid)
                    }
                }
            } catch {
                await MainActor.run { likeInProgress.remove(pid) }
            }
        }
    }

    private func printFeedToConsole(posts: [VKPost], nextFrom: String?) {
        print("[CleanFeedVK] ——— Лента (после фильтра): \(posts.count) постов ———")
        for (i, post) in posts.enumerated() {
            let preview = String(post.text.prefix(60))
            let more = post.text.count > 60 ? "…" : ""
            print("[\(i + 1)] \(preview)\(more) | date=\(post.date)")
        }
        if let next = nextFrom {
            print("next_from: \(next)")
        }
        print("[CleanFeedVK] ——— конец ленты ———")
    }
}

// MARK: - Состояние загрузки ленты

enum FeedLoadState {
    case idle
    case loading
    case loaded(count: Int)
    case failed(Error)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

#Preview {
    ContentView()
}
