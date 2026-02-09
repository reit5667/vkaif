import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Экран профиля: свой или друга. Composition: Header (users.get) + вкладки загружаются асинхронно и независимо через ProfileViewModel.
/// viewModel: если передан (таб «Профиль» в ContentView) — один экземпляр на всё приложение; иначе создаётся свой (профиль друга).
struct ProfileView: View {

    @ObservedObject var authService: AuthService
    @ObservedObject var viewModel: ProfileViewModel
    private var userId: Int? { viewModel.userId }

    @State private var selectedTab: ProfileTab = .wall
    @State private var isAvatarFullScreenPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarUploadInProgress = false
    @State private var avatarUploadMessage: String? = nil
    @State private var avatarUploadSuccess = false

    private let vkApi = VKApiService()

    init(authService: AuthService, viewModel: ProfileViewModel) {
        self.authService = authService
        self.viewModel = viewModel
    }

    private enum ProfileTab: String, CaseIterable {
        case wall = "Стена"
        case photo = "Фото"
        case friends = "Друзья"
        case groups = "Группы"
    }

    /// Группы — только у текущего пользователя; у друга вкладку не показываем.
    private var availableTabs: [ProfileTab] {
        userId == nil ? ProfileTab.allCases : [.wall, .photo, .friends]
    }

    var body: some View {
        Group {
            switch viewModel.userLoadState {
            case .idle, .loading:
                ProgressView("Загрузка профиля…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if let u = viewModel.user {
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
        .navigationTitle(viewModel.user?.displayName ?? "Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded = viewModel.userLoadState {
                    Button("Обновить") { viewModel.refreshAll() }
                }
            }
        }
        .onAppear { viewModel.loadProfileIfNeeded() }
    }

    /// Header + Picker сверху; контент вкладки (List) — отдельно с .frame(maxHeight: .infinity).
    /// List внутри ScrollView в SwiftUI даёт нулевую/схлопнутую высоту — контент не отображался.
    private func profileContent(user: VKUserDetail) -> some View {
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
                .id(tabContentId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .onChange(of: selectedTab) { _, newTab in
            loadTabIfNeeded(tab: newTab, user: user)
        }
        .fullScreenCover(isPresented: $isAvatarFullScreenPresented) {
            if let urlString = user.fullScreenAvatarURL, let url = URL(string: urlString) {
                FullScreenImageView(imageURL: url) { isAvatarFullScreenPresented = false }
            }
        }
        .onAppear {
            if !availableTabs.contains(selectedTab) {
                selectedTab = availableTabs.first ?? .wall
            }
        }
    }

    /// Идентификатор контента вкладки: при изменении данных SwiftUI пересоздаёт view.
    private var tabContentId: String {
        "albums-\(viewModel.albums.count)-friends-\(viewModel.friends.count)-groups-\(viewModel.groups.count)"
    }

    @ViewBuilder
    private func tabContent(user: VKUserDetail) -> some View {
        switch selectedTab {
        case .wall:
            ProfileWallTabView(
                posts: viewModel.wallPosts,
                profiles: viewModel.wallProfiles,
                groups: viewModel.wallGroups,
                loadState: viewModel.wallLoadState,
                user: user,
                authService: authService,
                isOwnProfile: userId == nil,
                onDeletePost: { viewModel.removeWallPost($0) },
                onRefresh: { await viewModel.loadWall(ownerId: user.id, forceRefresh: true) }
            )
        case .photo:
            ProfilePhotoTabView(
                albums: viewModel.albums,
                loadState: viewModel.albumsLoadState,
                authService: authService,
                ownerId: user.id,
                isOwnProfile: userId == nil,
                onRefresh: { await viewModel.loadAlbums(ownerId: user.id, forceRefresh: true) }
            )
        case .friends:
            ProfileFriendsTabView(
                friends: viewModel.friends,
                loadState: viewModel.friendsLoadState,
                authService: authService,
                onRefresh: { await viewModel.loadFriends(forceRefresh: true) }
            )
        case .groups:
            ProfileGroupsTabView(
                groups: viewModel.groups,
                loadState: viewModel.groupsLoadState,
                authService: authService,
                onRefresh: { await viewModel.loadGroups(forceRefresh: true) }
            )
        }
    }

    /// Подгрузить данные вкладки при переключении (второй шанс, если при первой загрузке не обновилось).
    private func loadTabIfNeeded(tab: ProfileTab, user: VKUserDetail) {
        switch tab {
        case .wall:
            Task { await viewModel.loadWall(ownerId: user.id, forceRefresh: false) }
        case .photo:
            Task { await viewModel.loadAlbums(ownerId: user.id, forceRefresh: false) }
        case .friends:
            Task { await viewModel.loadFriends(forceRefresh: false) }
        case .groups:
            Task { await viewModel.loadGroups(forceRefresh: false) }
        }
    }

    private func avatarSection(user: VKUserDetail) -> some View {
        VStack(spacing: 12) {
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

            if userId == nil {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(avatarUploadInProgress ? "Загрузка…" : "Изменить фото профиля", systemImage: "camera.fill")
                        .font(.subheadline)
                }
                .disabled(avatarUploadInProgress)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let item = newItem else { return }
                    Task { await uploadProfilePhoto(from: item) }
                }
                if let msg = avatarUploadMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(avatarUploadSuccess ? .green : .red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func uploadProfilePhoto(from item: PhotosPickerItem) async {
        guard let token = authService.accessToken else {
            await MainActor.run { avatarUploadMessage = "Нет доступа"; avatarUploadSuccess = false }
            return
        }
        await MainActor.run { avatarUploadInProgress = true; avatarUploadMessage = nil }
        defer { Task { @MainActor in avatarUploadInProgress = false } }
        do {
            guard let imageData = try await item.loadTransferable(type: ImageDataTransfer.self) else {
                await MainActor.run { avatarUploadMessage = "Не удалось загрузить фото"; avatarUploadSuccess = false }
                return
            }
            let jpegData = imageData.dataAsJpeg
            let uploadUrl = try await vkApi.getOwnerPhotoUploadServer(token: token)
            let (server, hash, photo) = try await vkApi.uploadOwnerPhotoToServer(uploadUrl: uploadUrl, imageData: jpegData)
            try await vkApi.saveOwnerPhoto(token: token, server: server, hash: hash, photo: photo)
            await MainActor.run {
                avatarUploadMessage = "Фото профиля обновлено"
                avatarUploadSuccess = true
                selectedPhotoItem = nil
                viewModel.refreshAll()
            }
        } catch {
            await MainActor.run {
                avatarUploadMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                avatarUploadSuccess = false
            }
        }
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
}

// MARK: - Состояние загрузки профиля

enum ProfileLoadState {
    case idle
    case loading
    case loaded
    case failed(Error)
    case notAuthenticated
}

/// Обёртка для профиля друга: создаёт и держит ViewModel (userId != nil). Для «свой профиль» в табе ViewModel передаётся из ContentView.
struct ProfileViewWrapper: View {
    @ObservedObject var authService: AuthService
    let userId: Int?

    @StateObject private var viewModel: ProfileViewModel

    init(authService: AuthService, userId: Int?) {
        self.authService = authService
        self.userId = userId
        _viewModel = StateObject(wrappedValue: ProfileViewModel(authService: authService, userId: userId))
    }

    var body: some View {
        ProfileView(authService: authService, viewModel: viewModel)
    }
}

// MARK: - Transferable для загрузки фото из галереи (PhotosPicker)
private struct ImageDataTransfer: Transferable {
    let data: Data
    var dataAsJpeg: Data {
        guard let ui = UIImage(data: data) else { return data }
        return ui.jpegData(compressionQuality: 0.9) ?? data
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in ImageDataTransfer(data: data) }
    }
}

#Preview("Свой профиль") {
    NavigationStack {
        ProfileViewWrapper(authService: AuthService(), userId: nil)
    }
}
