import SwiftUI

/// Элемент для fullScreenCover: индекс фото + уникальный id (чтобы повторный тап по той же картинке снова открывал).
private struct AlbumFullScreenItem: Identifiable {
    let index: Int
    let id = UUID()
}

/// Фото альбома (photos.get): сетка, тап — полноэкран; подгрузка +50 при достижении низа; сортировка по дате.
struct AlbumPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService: AuthService
    let ownerId: Int
    let albumId: Int
    let albumTitle: String
    /// true = альбом своего профиля (в альбоме «Фото профиля» показывать «Сделать фото профиля»).
    var isOwnProfile: Bool = false
    /// Обновить список альбомов после мутации фото, чтобы size в родительском экране не устаревал.
    var onAlbumListChanged: (() async -> Void)? = nil

    @State private var photos: [VKPhoto] = []
    @State private var totalCount: Int = 0
    @State private var loadState: AlbumPhotosLoadState = .idle
    @State private var loadMoreState: AlbumPhotosLoadState = .idle
    /// Индекс фото для fullscreen; nil = не показывать. Item-based, чтобы при первом тапе открывалась нужная картинка.
    @State private var fullScreenPhotoItem: AlbumFullScreenItem? = nil
    /// true = сначала новые (rev=1), false = сначала старые (rev=0).
    @State private var sortNewestFirst = true
    /// Переопределения лайков после likes.add/delete по фото (photoId -> count / liked).
    @State private var photoLikeOverrides: [Int: Int] = [:]
    @State private var photoLikedOverrides: [Int: Bool] = [:]
    @State private var photoLikeInProgress: Set<Int> = []
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteError = false
    @State private var shouldShowDeleteErrorAfterDismiss = false
    @State private var pendingDeletedPhotoId: Int? = nil
    @State private var shouldReloadAfterDismiss = false
    @State private var shouldRefreshAlbumListAfterDismiss = false
    /// Shared-объект для передачи photoId в onDeletePhoto. Живёт всё время жизни AlbumPhotosView.
    @State private var galleryDeleteRequest = GalleryDeleteRequest()

    private let vkApi = VKApiService()
    private let pageSize = 50
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    /// Примерная высота одной ячейки (квадрат) для расчёта spacer внизу — чтобы скролл имел «запас» под ещё не подгруженные фото.
    private let estimatedCellHeight: CGFloat = 120

    private var rev: Int { sortNewestFirst ? 1 : 0 }
    private var canLoadMore: Bool {
        loadState == .loaded && loadMoreState != .loading && photos.count < totalCount
    }

    private var makeProfilePhotoAction: ((String, Int, Int) async -> (Bool, String?))? {
        guard isOwnProfile, albumId == -6 else { return nil }
        return { [vkApi] token, oid, pid in
            do {
                try await vkApi.photosMakeCover(token: token, ownerId: oid, photoId: pid, albumId: -6)
                return (true, nil)
            } catch {
                AppLogger.shared.error("Gallery", "makeProfilePhoto failed", error: error)
                return (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Удаление фото из альбома (photos.delete).
    /// Во время открытого fullscreen не трогаем список/стейт экрана, только помечаем pending-удаление.
    /// Локальное удаление + reload + refresh списка альбомов выполняем уже в onDismiss галереи (handleGalleryDismiss).
    /// Ошибка: сохраняем сообщение — alert покажется после dismiss через handleGalleryDismiss.
    private func deletePhotoFromAlbum(token: String, ownerId: Int, photoId: Int) async -> Bool {
        let t = token.isEmpty ? (authService.accessToken ?? "") : token
        AppLogger.shared.info(
            "Gallery",
            "deletePhotoFromAlbum invoked ownerId=\(ownerId) photoId=\(photoId) tokenEmpty=\(t.isEmpty) photosCount=\(photos.count) totalCount=\(totalCount)"
        )
        guard !t.isEmpty else { return false }
        do {
            try await vkApi.photosDelete(token: t, ownerId: ownerId, photoId: photoId)
            AppLogger.shared.info("Gallery", "deletePhotoFromAlbum success photoId=\(photoId)")
            await MainActor.run {
                pendingDeletedPhotoId = photoId
                shouldReloadAfterDismiss = true
                shouldRefreshAlbumListAfterDismiss = true
            }
            return true
        } catch {
            AppLogger.shared.error("Gallery", "deletePhotoFromAlbum failed ownerId=\(ownerId) photoId=\(photoId)", error: error)
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Галерея закроется в любом случае (performDeleteCurrentPhoto вызывает onDismiss всегда).
            // Сохраняем ошибку — alert покажется сразу после dismiss (handleGalleryDismiss → showDeleteError).
            await MainActor.run {
                deleteErrorMessage = msg
                shouldShowDeleteErrorAfterDismiss = true
            }
            return false
        }
    }

    /// Высота spacer внизу сетки = сколько ещё строк фото не подгружено (чтобы контент ScrollView имел запас и скролл опускался).
    private var albumBottomSpacerHeight: CGFloat {
        let remaining = max(0, totalCount - photos.count)
        guard remaining > 0 else { return 0 }
        let rows = ceil(Double(remaining) / Double(columns.count))
        return CGFloat(rows) * estimatedCellHeight
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка фото…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if photos.isEmpty {
                    ContentUnavailableView("Нет фото", systemImage: "photo.on.rectangle.angled")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                photoCell(photo, index: index)
                                    .id(photo.id)
                            }
                            if canLoadMore {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear { loadMoreIfNeeded() }
                            }
                            if loadMoreState == .loading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            // Spacer внизу: резервируем высоту под ещё не подгруженные фото, чтобы скролл мог опускаться и триггер onAppear срабатывал.
                            if photos.count < totalCount {
                                Color.clear
                                    .frame(height: albumBottomSpacerHeight)
                            }
                        }
                        .padding(4)
                    }
                    .refreshable { reloadWithNewSort() }
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationTitle(albumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if sortNewestFirst { sortNewestFirst = false; reloadWithNewSort() }
                    } label: {
                        Label("Сначала старые", systemImage: sortNewestFirst ? "circle" : "checkmark.circle.fill")
                    }
                    Button {
                        if !sortNewestFirst { sortNewestFirst = true; reloadWithNewSort() }
                    } label: {
                        Label("Сначала новые", systemImage: !sortNewestFirst ? "circle" : "checkmark.circle.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $fullScreenPhotoItem) { item in
            fullScreenGalleryContent(item: item)
        }
        .onAppear {
            if loadState == .idle { loadPhotos(offset: 0, append: false) }
        }
        .alert("Не удалось удалить фото", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "Неизвестная ошибка")
        }
    }

    @ViewBuilder
    private func fullScreenGalleryContent(item: AlbumFullScreenItem) -> some View {
        // Фильтруем только фото с валидным URL — urls и photosWithURL синхронны по индексу.
        let photosWithURL = photos.filter { $0.displayURL.flatMap { URL(string: $0) } != nil }
        let urls = photosWithURL.compactMap { $0.displayURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            // item.index — индекс в исходном photos[]; ищем ближайший индекс в photosWithURL.
            let targetPhotoId = photos.indices.contains(item.index) ? photos[item.index].id : nil
            let galleryIndex = targetPhotoId.flatMap { id in photosWithURL.firstIndex(where: { $0.id == id }) } ?? 0
            albumGalleryView(urls: urls, photosWithURL: photosWithURL, galleryIndex: galleryIndex)
        }
    }

    private func albumGalleryView(urls: [URL], photosWithURL: [VKPhoto], galleryIndex: Int) -> FullScreenPhotoGalleryView {
        let idx = min(galleryIndex, photosWithURL.count - 1)
        let photo = photosWithURL.indices.contains(idx) ? photosWithURL[idx] : nil
        let onDismiss: () -> Void = { handleGalleryDismiss() }
        let likesCount: Int = photo.map { photoLikeOverrides[$0.id] ?? $0.likes?.count ?? 0 } ?? 0
        let commentsCount: Int = photo.map { $0.comments?.count ?? 0 } ?? 0
        let isLiked: Bool = photo.map { photoLikedOverrides[$0.id] ?? ($0.likes?.userLikes == 1) } ?? false
        let onLike: (() -> Void)? = photo.map { p in
            photoLikeInProgress.contains(p.id) ? nil : { likeTogglePhoto(photoId: p.id) }
        } ?? nil
        let photoCommentsContext: PhotoCommentsContext? = photo.map { PhotoCommentsContext(ownerId: ownerId, photoId: $0.id) }
        let getAccessToken: () -> String = { authService.accessToken ?? "" }
        var onDelete: ((String, Int, Int) async -> Bool)? = nil
        if isOwnProfile {
            // Читаем photoId из galleryDeleteRequest (обход ABI-бага Swift ARM64).
            // Gallery устанавливает galleryDeleteRequest.photoId синхронно до вызова этого замыкания.
            let dr = galleryDeleteRequest
            onDelete = { token, _, _ in
                AppLogger.shared.info("Gallery", "onDelete via deleteRequest photoId=\(dr.photoId)")
                return await deletePhotoFromAlbum(token: token, ownerId: ownerId, photoId: dr.photoId)
            }
        }
        // photoIds синхронен с urls по индексу (оба построены из photosWithURL).
        let photoIds: [PhotoSaveId] = photosWithURL.map { PhotoSaveId(ownerId: ownerId, photoId: $0.id, accessKey: $0.accessKey) }
        return FullScreenPhotoGalleryView(
            urls: urls,
            initialIndex: min(galleryIndex, urls.count - 1),
            onDismiss: onDismiss,
            likesCount: likesCount,
            commentsCount: commentsCount,
            isLiked: isLiked,
            onLike: onLike,
            photoCommentsContext: photoCommentsContext,
            authService: authService,
            photoIdsForSaving: photoIds,
            vkApi: vkApi,
            getAccessToken: getAccessToken,
            isSavedAlbum: (albumId == -15),
            initialAccessToken: authService.accessToken ?? "",
            isOwnPhotos: isOwnProfile,
            onDeletePhoto: onDelete,
            isProfileAlbum: (albumId == -6),
            onMakeProfilePhoto: makeProfilePhotoAction,
            galleryDeleteRequest: galleryDeleteRequest
        )
    }

    private func handleGalleryDismiss() {
        fullScreenPhotoItem = nil
        applyPendingDeletionIfNeeded()
        if shouldReloadAfterDismiss {
            shouldReloadAfterDismiss = false
            loadPhotos(offset: 0, append: false, preserveVisibleContent: true)
        }
        if shouldRefreshAlbumListAfterDismiss {
            shouldRefreshAlbumListAfterDismiss = false
            if let onAlbumListChanged {
                Task { await onAlbumListChanged() }
            }
        }
        if shouldShowDeleteErrorAfterDismiss {
            shouldShowDeleteErrorAfterDismiss = false
            showDeleteError = true
        }
    }

    private func applyPendingDeletionIfNeeded() {
        guard let pendingDeletedPhotoId else { return }
        let beforeCount = photos.count
        photos.removeAll { $0.id == pendingDeletedPhotoId }
        let removedCount = beforeCount - photos.count
        if removedCount > 0 {
            totalCount = max(0, totalCount - removedCount)
        }
        self.pendingDeletedPhotoId = nil
    }

    private func photoCell(_ photo: VKPhoto, index: Int) -> some View {
        Group {
            if let urlString = photo.thumbnailDisplayURL ?? photo.displayURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(minWidth: 0, minHeight: 0)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 0, minHeight: 0)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .onTapGesture {
            fullScreenPhotoItem = AlbumFullScreenItem(index: index)
        }
    }

    private func loadPhotos(offset: Int, append: Bool, preserveVisibleContent: Bool = false) {
        guard let token = authService.accessToken else { return }
        if append {
            loadMoreState = .loading
        } else if !preserveVisibleContent || photos.isEmpty {
            loadState = .loading
        }
        Task {
            do {
                let response = try await vkApi.getPhotos(
                    token: token,
                    ownerId: ownerId,
                    albumId: albumId,
                    count: pageSize,
                    offset: offset,
                    rev: rev
                )
                // Диагностика для альбома «Сохранённые» (-15): логируем id/owner_id первых фото
                if albumId == -15, let first = response.items.first {
                    AppLogger.shared.info("AlbumDebug", "album=-15 totalCount=\(response.count) first.id=\(first.id) first.ownerId=\(String(describing: first.ownerId)) albumOwnerId=\(ownerId)")
                }
                await MainActor.run {
                    if append {
                        photos.append(contentsOf: response.items)
                        loadMoreState = .idle
                        if response.items.count >= pageSize {
                            totalCount = max(totalCount, photos.count + 1)
                        }
                    } else {
                        photos = response.items
                        totalCount = response.count
                        if response.items.count >= pageSize && response.count <= response.items.count {
                            totalCount = max(response.count, response.items.count + 1)
                        }
                        loadState = .loaded
                    }
                }
            } catch {
                await MainActor.run {
                    if append { loadMoreState = .failed(error) }
                    else if !preserveVisibleContent || photos.isEmpty { loadState = .failed(error) }
                }
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard canLoadMore else { return }
        loadPhotos(offset: photos.count, append: true)
    }

    private func reloadWithNewSort() {
        photos = []
        totalCount = 0
        loadPhotos(offset: 0, append: false)
    }

    /// Toggle лайка фото: likes.add / likes.delete type "photo".
    private func likeTogglePhoto(photoId: Int) {
        guard let token = authService.accessToken else { return }
        if photoLikeInProgress.contains(photoId) { return }
        let isLiked = photoLikedOverrides[photoId] ?? (photos.first(where: { $0.id == photoId })?.likes?.userLikes == 1)
        photoLikeInProgress.insert(photoId)
        Task {
            do {
                let newCount: Int
                if isLiked {
                    newCount = try await vkApi.likesDelete(
                        token: token,
                        type: "photo",
                        ownerId: ownerId,
                        itemId: photoId
                    )
                    await MainActor.run {
                        photoLikeOverrides[photoId] = newCount
                        photoLikedOverrides[photoId] = false
                        photoLikeInProgress.remove(photoId)
                    }
                } else {
                    newCount = try await vkApi.likesAdd(
                        token: token,
                        type: "photo",
                        ownerId: ownerId,
                        itemId: photoId
                    )
                    await MainActor.run {
                        photoLikeOverrides[photoId] = newCount
                        photoLikedOverrides[photoId] = true
                        photoLikeInProgress.remove(photoId)
                    }
                }
            } catch {
                await MainActor.run { photoLikeInProgress.remove(photoId) }
            }
        }
    }
}

enum AlbumPhotosLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(Error)

    static func == (lhs: AlbumPhotosLoadState, rhs: AlbumPhotosLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
