import SwiftUI

// MARK: - Вкладка «Фото»: альбомы + Сохранённые (данные передаются из ProfileView)

struct ProfilePhotoTabView: View {
    let albums: [VKAlbum]
    let loadState: ProfileTabLoadState
    @ObservedObject var authService: AuthService
    let ownerId: Int
    var onRefresh: () async -> Void

    private static let savedAlbumId = -15
    /// VK: фото профиля (стена).
    private static let profileAlbumId = -6

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
                        NavigationLink(value: AlbumDestination(ownerId: ownerId, albumId: Self.profileAlbumId, title: "Фото профиля")) {
                            Label("Фото профиля", systemImage: "person.crop.rectangle.stack")
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
                    "Ошибка загрузки альбомов",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("\(error.localizedDescription)\n\nПерелогиньтесь (Выйти → Войти) и выдайте права: друзья, фото, группы.")
                )
            }
        }
        .refreshable { await onRefresh() }
        .navigationDestination(for: AlbumDestination.self) { dest in
            AlbumPhotosView(
                authService: authService,
                ownerId: dest.ownerId,
                albumId: dest.albumId,
                albumTitle: dest.title
            )
        }
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
}

struct AlbumDestination: Hashable {
    let ownerId: Int
    let albumId: Int
    let title: String
}

/// Цель навигации из вкладки «Группы» профиля (отдельно от Int для друзей).
struct GroupDestination: Hashable {
    let groupId: Int
}

// MARK: - Вкладка «Друзья» (данные передаются из ProfileView)

struct ProfileFriendsTabView: View {
    let friends: [VKFriend]
    let loadState: ProfileTabLoadState
    @ObservedObject var authService: AuthService
    var onRefresh: () async -> Void

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
                    "Ошибка загрузки друзей",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("\(error.localizedDescription)\n\nПерелогиньтесь (Выйти → Войти) и выдайте права: друзья, фото, группы.")
                )
            }
        }
        .refreshable { await onRefresh() }
        .navigationDestination(for: Int.self) { friendId in
            ProfileViewWrapper(authService: authService, userId: friendId)
        }
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
}

// MARK: - Вкладка «Группы» (данные передаются из ProfileView)

struct ProfileGroupsTabView: View {
    let groups: [VKGroup]
    let loadState: ProfileTabLoadState
    @ObservedObject var authService: AuthService
    var onRefresh: () async -> Void

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
                        NavigationLink(value: GroupDestination(groupId: group.id)) {
                            HStack(spacing: 12) {
                                groupAvatar(group)
                                Text(group.name ?? "Группа \(group.id)")
                                    .font(.body)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: GroupDestination.self) { dest in
                        GroupWallView(authService: authService, groupId: dest.groupId)
                    }
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка загрузки групп",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("\(error.localizedDescription)\n\nПерелогиньтесь (Выйти → Войти) и выдайте права: друзья, фото, группы.")
                )
            }
        }
        .refreshable { await onRefresh() }
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
}

enum ProfileTabLoadState {
    case idle
    case loading
    case loaded
    case failed(Error)
}
