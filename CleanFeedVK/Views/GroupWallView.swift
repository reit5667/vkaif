import SwiftUI

/// Страница группы: инфо (groups.getById) + лента постов (wall.get).
struct GroupWallView: View {
    @ObservedObject var authService: AuthService
    /// ID группы (положительное число, например 12345).
    let groupId: Int

    @State private var group: VKGroup?
    @State private var posts: [VKPost] = []
    @State private var loadState: GroupWallLoadState = .idle

    private let vkApi = VKApiService()
    private var ownerId: Int { -groupId }

    enum GroupWallLoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let g = group {
                            groupHeader(group: g)
                        }
                        ForEach(posts, id: \.postId) { post in
                            PostCellView(
                                post: post,
                                authorName: group?.name ?? "Группа",
                                authorAvatarURL: group?.photo50,
                                relativeDate: relativeDateString(from: post.date),
                                authService: nil,
                                feedDestination: nil
                            )
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationTitle(group?.name ?? "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded = loadState {
                    Button("Обновить") { load() }
                }
            }
        }
        .onAppear { load() }
    }

    private func groupHeader(group: VKGroup) -> some View {
        HStack(spacing: 12) {
            Group {
                if let urlString = group.photo50, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure, .empty: Image(systemName: "person.3.fill").resizable().foregroundStyle(.secondary)
                        @unknown default: EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.3.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            Text(group.name ?? "Группа \(group.id)")
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func load() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                async let groupTask = vkApi.getGroupById(token: token, groupId: groupId)
                async let wallTask = vkApi.getWall(token: token, ownerId: ownerId)
                let g = try? await groupTask
                let wall = try await wallTask
                await MainActor.run {
                    group = g
                    posts = wall.items
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }
}
