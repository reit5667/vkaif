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
    @State private var videoPlayerURL: URL? = nil
    @State private var videoPlayerPost: VKPost? = nil
    /// Переопределения опросов после голосования. Ключ: "ownerId_postId_pollId".
    @State private var pollVoteOverrides: [String: PollVoteOverride] = [:]
    @State private var pollVoteInProgress: Set<String> = []
    /// Переопределения счётчика репостов после wall.repost (postId -> count).
    @State private var postRepostOverrides: [String: Int] = [:]
    @State private var repostInProgress: Set<String> = []
    @State private var showRepostDMStub = false
    /// ID текущего пользователя (для показа «Удалить» только у своих постов). Заполняется при loadFeed.
    @State private var currentUserId: Int? = nil
    @State private var deleteInProgress: Set<String> = []
    @State private var pinInProgress: Set<String> = []
    /// Переопределение «закреплён» после wall.pin / wall.unpin (postId -> true/false).
    @State private var postPinnedOverrides: [String: Bool] = [:]

    private let vkApi = VKApiService()
    private let feedFilter = FeedFilter(blacklistKeywords: []) // позже — настройки

    @Environment(\.scenePhase) private var scenePhase

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
                            FriendsTabView(authService: authService)
                        }
                        .tabItem { Label("Друзья", systemImage: "person.2") }
                        NavigationStack {
                            MessagesTabView(authService: authService)
                        }
                        .tabItem { Label("Сообщения", systemImage: "bubble.left.and.bubble.right") }
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
            .onChange(of: scenePhase) { _, new in
                if new == .active, case .authenticated = authService.state {
                    loadFeed()
                }
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
        .onAppear {
            if case .authenticated = authService.state, case .idle = feedLoadState {
                loadFeed()
            }
        }
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
                    postRepostOverrides = [:]
                    repostInProgress = []
                    pollVoteOverrides = [:]
                    pollVoteInProgress = []
                    currentUserId = nil
                    deleteInProgress = []
                }
            }
        }
    }

    // MARK: - Лента постов (LazyVStack)

    private var feedListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(feedPosts, id: \.postId) { post in
                    feedPostRow(post)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .fullScreenCover(isPresented: Binding(
            get: { videoPlayerURL != nil },
            set: { if !$0 { videoPlayerURL = nil; videoPlayerPost = nil } }
        )) {
            if let url = videoPlayerURL {
                videoPlayerContent(url: url)
            }
        }
        .overlay(alignment: .top) {
            if feedLoadState.isLoading {
                ProgressView("Загрузка…")
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .alert("Репост в личку", isPresented: $showRepostDMStub) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Скоро. Раздел сообщений в разработке.")
        }
    }

    @ViewBuilder
    private func videoPlayerContent(url: URL) -> some View {
        let post = videoPlayerPost
        let ctx: VideoPlayerPostContext? = post.map { p in
            VideoPlayerPostContext(
                likesCount: postLikeOverrides[p.postId] ?? p.likesCount,
                commentsCount: p.commentsCount,
                isLiked: postLikedOverrides[p.postId] ?? (p.likes?.userLikes == 1),
                onLike: { likeToggle(p) },
                onTapComments: {
                    commentsContext = PostCommentsContext(
                        ownerId: p.ownerId ?? p.fromId ?? 0,
                        postId: p.id,
                        totalCount: p.commentsCount
                    )
                }
            )
        }
        VideoPlayerView(url: url, onDismiss: { videoPlayerURL = nil; videoPlayerPost = nil }, postContext: ctx)
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

    private func feedPostRow(_ post: VKPost) -> some View {
        let ownerId = post.ownerId ?? post.fromId ?? 0
        let isOwnPost = ownerId > 0 && currentUserId != nil && ownerId == currentUserId
        let repostCount = postRepostOverrides[post.postId]
        let repostLoading = repostInProgress.contains(post.postId)
        let repostToWallAction: (() -> Void)? = repostLoading ? nil : { repostToWall(post) }
        let tapComments: () -> Void = {
            commentsContext = PostCommentsContext(
                ownerId: post.ownerId ?? post.fromId ?? 0,
                postId: post.id,
                totalCount: post.commentsCount
            )
        }
        let likeAction: (() -> Void)? = likeInProgress.contains(post.postId) ? nil : { likeToggle(post) }
        let tapVideo: (VKVideo, Int, VKPost) async -> Void = { video, ownerId, post in
            var url: URL?
            if let p = video.player, let u = URL(string: p) {
                url = u
            } else {
                let token = await MainActor.run { authService.accessToken } ?? ""
                if !token.isEmpty,
                   let res = try? await vkApi.getVideo(token: token, videos: video.videoGetId(ownerFallback: ownerId)),
                   let first = res.items.first,
                   let playerURL = first.player {
                    url = URL(string: playerURL)
                }
            }
            await MainActor.run {
                videoPlayerURL = url
                videoPlayerPost = post
            }
        }
        let onPollVoteAction: (VKPost, VKPoll, Int) -> Void = { p, poll, answerId in
            pollVote(post: p, poll: poll, answerId: answerId)
        }
        let onDeleteAction: (() -> Void)? = isOwnPost ? { deletePost(post) } : nil
        let deletePhotoClosure: (String, Int, Int) async -> Bool = { token, ownerId, photoId in
            await deletePhotoFromPost(token: token, ownerId: ownerId, photoId: photoId)
        }
        let makeProfilePhotoClosure: (String, Int, Int) async -> (Bool, String?) = { token, ownerId, photoId in
            await makeProfilePhotoFromPost(token: token, ownerId: ownerId, photoId: photoId)
        }
        let onDeletePhotoAction: ((String, Int, Int) async -> Bool)? = isOwnPost ? Optional(deletePhotoClosure) : nil
        let onMakeProfilePhotoAction: ((String, Int, Int) async -> (Bool, String?))? = isOwnPost ? Optional(makeProfilePhotoClosure) : nil
        return FeedPostRowCell(
            post: post,
            authorName: authorName(for: post),
            authorAvatarURL: authorAvatarURL(for: post),
            relativeDate: relativeDateString(from: post.date),
            profiles: feedProfiles,
            groups: feedGroups,
            authService: authService,
            feedDestination: feedDestination(for: post),
            onTapComments: tapComments,
            likesCountOverride: postLikeOverrides[post.postId],
            isLikedOverride: postLikedOverrides[post.postId],
            likeInProgress: likeInProgress.contains(post.postId),
            onLike: likeAction,
            onTapVideo: tapVideo,
            pollVoteOverrides: pollVoteOverrides,
            onPollVote: onPollVoteAction,
            pollVoteInProgress: pollVoteInProgress,
            repostsCountOverride: repostCount,
            onRepostToWall: repostToWallAction,
            onRepostToDM: { showRepostDMStub = true },
            repostInProgress: repostLoading,
            canDeletePost: isOwnPost,
            onDelete: onDeleteAction,
            deleteInProgress: deleteInProgress.contains(post.postId),
            canPinPost: isOwnPost,
            isPinned: postPinnedOverrides[post.postId] ?? (post.isPinned == 1),
            onPin: { pinPost(post) },
            onUnpin: { unpinPost(post) },
            pinInProgress: pinInProgress.contains(post.postId),
            onDeletePhoto: onDeletePhotoAction,
            onMakeProfilePhoto: onMakeProfilePhotoAction,
            onRepostSuccessFromGallery: { newCount in postRepostOverrides[post.postId] = newCount },
            vkApi: vkApi,
            getAccessToken: { authService.accessToken ?? "" }
        )
    }

    /// Сделать фото главным в профиле (photos.makeCover). Для своих постов из fullscreen галереи.
    private func makeProfilePhotoFromPost(token: String, ownerId: Int, photoId: Int) async -> (Bool, String?) {
        do {
            try await vkApi.photosMakeCover(token: token, ownerId: ownerId, photoId: photoId, albumId: -6)
            return (true, nil)
        } catch {
            AppLogger.shared.error("Feed", "makeProfilePhoto failed", error: error)
            return (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Удаление фото (photos.delete). Для своих постов из fullscreen галереи. Возвращает true при успехе.
    private func deletePhotoFromPost(token: String, ownerId: Int, photoId: Int) async -> Bool {
        do {
            try await vkApi.photosDelete(token: token, ownerId: ownerId, photoId: photoId)
            return true
        } catch {
            return false
        }
    }

    /// Удаление поста (wall.delete). При успехе пост убирается из ленты.
    private func deletePost(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let pid = post.postId
        if deleteInProgress.contains(pid) { return }
        deleteInProgress.insert(pid)
        Task {
            do {
                try await vkApi.wallDelete(token: token, ownerId: ownerId, postId: post.id)
                await MainActor.run {
                    feedPosts.removeAll { $0.postId == pid }
                    deleteInProgress.remove(pid)
                }
            } catch {
                await MainActor.run { deleteInProgress.remove(pid) }
            }
        }
    }

    /// Закрепить пост (wall.pin). Только свои посты.
    private func pinPost(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let pid = post.postId
        if pinInProgress.contains(pid) { return }
        pinInProgress.insert(pid)
        Task {
            do {
                try await vkApi.wallPin(token: token, ownerId: ownerId, postId: post.id)
                await MainActor.run {
                    postPinnedOverrides[pid] = true
                    pinInProgress.remove(pid)
                }
            } catch {
                await MainActor.run { pinInProgress.remove(pid) }
            }
        }
    }

    /// Открепить пост (wall.unpin).
    private func unpinPost(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let pid = post.postId
        if pinInProgress.contains(pid) { return }
        pinInProgress.insert(pid)
        Task {
            do {
                try await vkApi.wallUnpin(token: token, ownerId: ownerId, postId: post.id)
                await MainActor.run {
                    postPinnedOverrides[pid] = false
                    pinInProgress.remove(pid)
                }
            } catch {
                await MainActor.run { pinInProgress.remove(pid) }
            }
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
                if await MainActor.run(body: { currentUserId }) == nil,
                   let users = try? await vkApi.getUsers(token: token),
                   let first = users.first {
                    await MainActor.run { currentUserId = first.id }
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

    /// Репост поста на свою стену (wall.repost). object = "wall{owner_id}_{post_id}".
    private func repostToWall(_ post: VKPost) {
        guard let token = authService.accessToken else { return }
        let ownerId = post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let pid = post.postId
        if repostInProgress.contains(pid) { return }
        repostInProgress.insert(pid)
        let object = "wall\(ownerId)_\(post.id)"
        Task {
            do {
                let response = try await vkApi.wallRepost(token: token, object: object)
                await MainActor.run {
                    if let newCount = response.repostsCount {
                        postRepostOverrides[pid] = newCount
                    }
                    repostInProgress.remove(pid)
                }
            } catch {
                await MainActor.run { repostInProgress.remove(pid) }
            }
        }
    }

    private func pollVote(post: VKPost, poll: VKPoll, answerId: Int) {
        guard let token = authService.accessToken else { return }
        let ownerId = poll.ownerId ?? post.ownerId ?? post.fromId ?? 0
        guard ownerId != 0 else { return }
        let key = "\(ownerId)_\(post.id)_\(poll.id)"
        if pollVoteInProgress.contains(key) { return }
        pollVoteInProgress.insert(key)
        Task {
            do {
                try await vkApi.addPollVote(
                    token: token,
                    ownerId: ownerId,
                    pollId: poll.id,
                    answerId: answerId
                )
                let totalBefore = poll.votes ?? 0
                let totalVotes = totalBefore + 1
                var answerVotes: [Int: Int] = [:]
                for a in poll.answers ?? [] {
                    let v = a.votes ?? 0
                    answerVotes[a.id] = a.id == answerId ? v + 1 : v
                }
                await MainActor.run {
                    pollVoteOverrides[key] = PollVoteOverride(
                        selectedAnswerId: answerId,
                        totalVotes: totalVotes,
                        answerVotes: answerVotes
                    )
                    pollVoteInProgress.remove(key)
                }
            } catch {
                await MainActor.run { pollVoteInProgress.remove(key) }
            }
        }
    }

    private func addPhotoToSaved(token: String, ownerId: Int, photoId: Int, accessKey: String? = nil) async -> Bool {
        let t = token
        let o = ownerId
        let p = photoId
        let a = accessKey ?? ""
        guard !t.isEmpty else {
            AppLogger.shared.error("Gallery", "addPhotoToSaved: empty token")
            return false
        }
        do {
            _ = try await vkApi.photosCopy(token: t, ownerId: o, photoId: p, accessKey: a)
            return true
        } catch {
            AppLogger.shared.error("Gallery", "addPhotoToSaved failed ownerId=\(o) photoId=\(p)", error: error)
            return false
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

// MARK: - Заглушки табов «Друзья» и «Сообщения»

private struct FriendsStubView: View {
    var body: some View {
        ContentUnavailableView(
            "Друзья",
            systemImage: "person.2",
            description: Text("Раздел в разработке. Список друзей доступен во вкладке «Профиль».")
        )
        .navigationTitle("Друзья")
    }
}

#Preview {
    ContentView()
}
