import SwiftUI

struct ContentView: View {

    @StateObject private var authService = AuthService()
    @State private var showAuthView = false
    @State private var feedLoadState: FeedLoadState = .idle
    @State private var feedPosts: [VKPost] = []
    @State private var feedProfiles: [VKProfile] = []
    @State private var feedGroups: [VKGroup] = []
    @State private var nextFrom: String? = nil       // курсор для подгрузки
    @State private var isLoadingMore: Bool = false  // подгрузка в конец

    private let vkApi = VKApiService()
    private let feedFilter = FeedFilter(blacklistKeywords: []) // позже — настройки

    var body: some View {
        NavigationView {
            Group {
                if !feedPosts.isEmpty {
                    feedListView
                } else {
                    mainContentStack
                }
            }
            .navigationTitle("Главная")
            .sheet(isPresented: $showAuthView) {
                AuthView(authService: authService)
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
                        relativeDate: relativeDateString(from: post.date)
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
        .overlay(alignment: .top) {
            if feedLoadState.isLoading {
                ProgressView("Загрузка…")
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
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
                }
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
