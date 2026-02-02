import SwiftUI

// MARK: - Вкладка «Фото»: альбомы + Сохранённые

struct ProfilePhotoTabView: View {
    @ObservedObject var authService: AuthService
    let ownerId: Int

    @State private var albums: [VKAlbum] = []
    @State private var loadState: ProfileTabLoadState = .idle

    private let vkApi = VKApiService()
    private static let savedAlbumId = -15

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка альбомов…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                List {
                    Section {
                        NavigationLink(value: AlbumDestination(ownerId: ownerId, albumId: Self.savedAlbumId, title: "Сохранённые фото")) {
                            Label("Сохранённые фото", systemImage: "square.and.arrow.down.fill")
                        }
                    }
                    Section("Альбомы") {
                        ForEach(albums, id: \.id) { album in
                            NavigationLink(value: AlbumDestination(ownerId: ownerId, albumId: album.id, title: album.title)) {
                                HStack(spacing: 12) {
                                    albumThumb(album)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.title)
                                            .font(.body)
                                        Text("\(album.size) фото")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationDestination(for: AlbumDestination.self) { dest in
            AlbumPhotosView(
                authService: authService,
                ownerId: dest.ownerId,
                albumId: dest.albumId,
                albumTitle: dest.title
            )
        }
        .onAppear { loadAlbums() }
    }

    private func albumThumb(_ album: VKAlbum) -> some View {
        Group {
            if let urlString = album.thumbURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure, .empty: Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .cornerRadius(8)
    }

    private func loadAlbums() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                let response = try await vkApi.getPhotosAlbums(token: token, ownerId: ownerId)
                await MainActor.run {
                    albums = response.items
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }
}

struct AlbumDestination: Hashable {
    let ownerId: Int
    let albumId: Int
    let title: String
}

// MARK: - Вкладка «Друзья»

struct ProfileFriendsTabView: View {
    @ObservedObject var authService: AuthService
    let ownerId: Int?

    @State private var friends: [VKFriend] = []
    @State private var loadState: ProfileTabLoadState = .idle

    private let vkApi = VKApiService()

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка друзей…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if friends.isEmpty {
                    ContentUnavailableView("Нет друзей", systemImage: "person.2")
                } else {
                    List(friends, id: \.id) { friend in
                        NavigationLink(value: friend.id) {
                            HStack(spacing: 12) {
                                friendAvatar(friend)
                                Text(friend.displayName)
                                    .font(.body)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationDestination(for: Int.self) { friendId in
            ProfileView(authService: authService, userId: friendId)
        }
        .onAppear { loadFriends() }
    }

    private func friendAvatar(_ friend: VKFriend) -> some View {
        Group {
            if let urlString = friend.photo50, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure, .empty: Image(systemName: "person.circle.fill").resizable().foregroundStyle(.secondary)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func loadFriends() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                let response = try await vkApi.getFriends(token: token, userId: ownerId)
                await MainActor.run {
                    friends = response.items
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }
}

// MARK: - Вкладка «Группы»

struct ProfileGroupsTabView: View {
    @ObservedObject var authService: AuthService

    @State private var groups: [VKGroup] = []
    @State private var loadState: ProfileTabLoadState = .idle

    private let vkApi = VKApiService()

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка групп…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if groups.isEmpty {
                    ContentUnavailableView("Нет групп", systemImage: "person.3")
                } else {
                    List(groups, id: \.id) { group in
                        HStack(spacing: 12) {
                            groupAvatar(group)
                            Text(group.name ?? "Группа \(group.id)")
                                .font(.body)
                        }
                        // TODO: переход на страницу группы (wall)
                    }
                    .listStyle(.insetGrouped)
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .onAppear { loadGroups() }
    }

    private func groupAvatar(_ group: VKGroup) -> some View {
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
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func loadGroups() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                let response = try await vkApi.getGroups(token: token)
                await MainActor.run {
                    groups = response.items
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }
}

enum ProfileTabLoadState {
    case idle
    case loading
    case loaded
    case failed(Error)
}
