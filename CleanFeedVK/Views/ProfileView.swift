import SwiftUI

/// Экран профиля: свой или друга (users.get).
/// При userId == nil загружается текущий пользователь.
struct ProfileView: View {

    @ObservedObject var authService: AuthService
    /// ID друга для просмотра; nil = свой профиль.
    var userId: Int? = nil

    @State private var loadState: ProfileLoadState = .idle
    @State private var user: VKUserDetail?
    @State private var selectedTab: ProfileTab = .photo
    @State private var isAvatarFullScreenPresented = false

    private let vkApi = VKApiService()

    private enum ProfileTab: String, CaseIterable {
        case photo = "Фото"
        case friends = "Друзья"
        case groups = "Группы"
    }

    /// Группы — только у текущего пользователя; у друга вкладку не показываем.
    private var availableTabs: [ProfileTab] {
        userId == nil ? ProfileTab.allCases : [.photo, .friends]
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка профиля…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if let u = user {
                    profileContent(user: u)
                } else {
                    ContentUnavailableView("Профиль не найден", systemImage: "person.slash")
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            case .notAuthenticated:
                ContentUnavailableView(
                    "Войдите в аккаунт",
                    systemImage: "person.badge.key",
                    description: Text("Профиль доступен после авторизации")
                )
            }
        }
        .navigationTitle(user?.displayName ?? "Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded = loadState {
                    Button("Обновить") { loadProfile() }
                }
            }
        }
        .onAppear { loadProfile() }
    }

    private func profileContent(user: VKUserDetail) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                avatarSection(user: user)
                nameSection(user: user)
                if let status = user.status, !status.isEmpty {
                    statusSection(status: status)
                }
                Picker("", selection: $selectedTab) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                tabContent(user: user)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $isAvatarFullScreenPresented) {
            if let urlString = user.avatarURL, let url = URL(string: urlString) {
                FullScreenImageView(imageURL: url) { isAvatarFullScreenPresented = false }
            }
        }
        .onAppear {
            if !availableTabs.contains(selectedTab) {
                selectedTab = availableTabs.first ?? .photo
            }
        }
    }

    @ViewBuilder
    private func tabContent(user: VKUserDetail) -> some View {
        switch selectedTab {
        case .photo:
            ProfilePhotoTabView(authService: authService, ownerId: user.id)
        case .friends:
            ProfileFriendsTabView(authService: authService, ownerId: userId ?? user.id)
        case .groups:
            ProfileGroupsTabView(authService: authService)
        }
    }

    private func avatarSection(user: VKUserDetail) -> some View {
        Group {
            if let urlString = user.avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .frame(width: 120, height: 120)
            }
        }
        .onTapGesture { isAvatarFullScreenPresented = true }
    }

    private func nameSection(user: VKUserDetail) -> some View {
        Text(user.displayName)
            .font(.title2)
            .fontWeight(.semibold)
    }

    private func statusSection(status: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Статус")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(status)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func loadProfile() {
        guard let token = authService.accessToken else {
            loadState = .notAuthenticated
            return
        }
        loadState = .loading
        let ids: [String]? = userId.map { [String(describing: $0)] }
        Task {
            do {
                let users = try await vkApi.getUsers(token: token, userIds: ids)
                await MainActor.run {
                    user = users.first
                    loadState = .loaded
                }
            } catch {
                await MainActor.run {
                    loadState = .failed(error)
                }
            }
        }
    }
}

// MARK: - Состояние загрузки профиля

enum ProfileLoadState {
    case idle
    case loading
    case loaded
    case failed(Error)
    case notAuthenticated
}

#Preview("Свой профиль") {
    NavigationStack {
        ProfileView(authService: AuthService())
    }
}
