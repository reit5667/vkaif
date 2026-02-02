import SwiftUI

struct ContentView: View {

    @StateObject private var authService = AuthService()
    @State private var showAuthView = false
    @State private var feedLoadState: FeedLoadState = .idle

    private let vkApi = VKApiService()
    private let feedFilter = FeedFilter(blacklistKeywords: []) // позже — настройки

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("CleanFeedVK")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Divider()

                // Статус авторизации
                statusSection

                // Кнопки действий
                actionButtons

                // Результат загрузки ленты
                feedResultView
            }
            .padding()
            .navigationTitle("Главная")
            .sheet(isPresented: $showAuthView) {
                AuthView(authService: authService)
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
                    feedLoadState = .loaded(count: filtered.count)
                }
                // Вывод в консоль (уже отфильтрованная лента)
                printFeedToConsole(posts: filtered, nextFrom: response.nextFrom)
            } catch {
                await MainActor.run {
                    feedLoadState = .failed(error)
                }
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
