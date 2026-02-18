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
    /// Для вкладки «Стена» — header и посты в одном ScrollView.
    private func profileContent(user: VKUserDetail) -> some View {
        let header = VStack(spacing: 24) {
            avatarSection(user: user)
            nameSection(user: user)
                .padding(.top, 4)
            if let status = user.status, !status.isEmpty {
                statusSection(status: status)
            }
            Picker("", selection: $selectedTab) {
                ForEach(availableTabs, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)

        /// Стена, Группы, Друзья — один ScrollView (header + контент скроллятся вместе). Фото — отдельная вкладка с альбомами.
        return Group {
            if selectedTab == .wall || selectedTab == .groups || selectedTab == .friends {
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        tabContent(user: user)
                            .id(tabContentId)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 20) {
                    header
                    tabContent(user: user)
                        .id(tabContentId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            loadTabIfNeeded(tab: newTab, user: user)
        }
        .fullScreenCover(isPresented: $isAvatarFullScreenPresented) {
            profileMainPhotoGalleryView(user: user)
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
                onRefresh: { await viewModel.loadWall(ownerId: user.id, forceRefresh: true) },
                embeddedInScroll: true
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
                onRefresh: { await viewModel.loadFriends(forceRefresh: true) },
                embeddedInScroll: true
            )
        case .groups:
            ProfileGroupsTabView(
                groups: viewModel.groups,
                loadState: viewModel.groupsLoadState,
                authService: authService,
                onRefresh: { await viewModel.loadGroups(forceRefresh: true) },
                onLeaveSuccess: { Task { await viewModel.loadGroups(forceRefresh: true) } },
                embeddedInScroll: true
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

    /// URL главного фото: из альбома «Фото профиля» (photos.get -6) в полном размере; иначе fallback из users.get.
    private func mainPhotoURL(user: VKUserDetail) -> String? {
        viewModel.profileMainPhoto?.displayURL ?? user.fullScreenAvatarURL
    }

    /// Fullscreen-галерея главного фото профиля: тот же экран, что у фото из ленты/альбома (лайки, комментарии, меню).
    @ViewBuilder
    private func profileMainPhotoGalleryView(user: VKUserDetail) -> some View {
        if let urlString = mainPhotoURL(user: user), let url = URL(string: urlString) {
            let photo = viewModel.profileMainPhoto
            let ownerId = user.id
            FullScreenPhotoGalleryView(
                urls: [url],
                initialIndex: 0,
                onDismiss: { isAvatarFullScreenPresented = false },
                likesCount: photo?.likes?.count,
                commentsCount: photo?.comments?.count,
                isLiked: photo?.likes?.userLikes == 1,
                onLike: nil,
                photoCommentsContext: photo.map { PhotoCommentsContext(ownerId: ownerId, photoId: $0.id) },
                authService: authService,
                photoIdsForSaving: photo.flatMap { p in
                    guard let oid = p.ownerId else { return nil }
                    return [PhotoSaveId(ownerId: oid, photoId: p.id, accessKey: p.accessKey)]
                },
                vkApi: vkApi,
                getAccessToken: { authService.accessToken ?? "" },
                isOwnPhotos: userId == nil,
                isProfileAlbum: (userId == nil)
            )
        }
    }

    /// Шапка профиля: главное фото (полноразмерное из альбома -6, обрезка под прямоугольник с закруглёнными нижними углами), ниже — «Изменить фото» и имя.
    private func avatarSection(user: VKUserDetail) -> some View {
        VStack(spacing: 16) {
            Group {
                if let urlString = mainPhotoURL(user: user), let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "person.crop.rectangle.fill")
                                .resizable()
                                .scaledToFill()
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 16, bottomTrailing: 16, topTrailing: 0)
                        )
                    )
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .overlay(
                            Image(systemName: "person.crop.rectangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        )
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 16, bottomTrailing: 16, topTrailing: 0)
                            )
                        )
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
