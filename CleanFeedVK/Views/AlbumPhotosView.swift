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

    private let vkApi = VKApiService()
    private let pageSize = 50
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    /// Примерная высота одной ячейки (квадрат) для расчёта spacer внизу — чтобы скролл имел «запас» под ещё не подгруженные фото.
    private let estimatedCellHeight: CGFloat = 120

    private var rev: Int { sortNewestFirst ? 1 : 0 }
    private var canLoadMore: Bool {
        loadState == .loaded && loadMoreState != .loading && photos.count < totalCount
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
            let urls = photos.compactMap { $0.displayURL }.compactMap { URL(string: $0) }
            let idx = min(item.index, photos.count - 1)
            let photo = photos.indices.contains(idx) ? photos[idx] : nil
            if !urls.isEmpty {
                FullScreenPhotoGalleryView(
                    urls: urls,
                    initialIndex: min(item.index, urls.count - 1),
                    onDismiss: { fullScreenPhotoItem = nil },
                    likesCount: photo.map { photoLikeOverrides[$0.id] ?? $0.likes?.count ?? 0 } ?? 0,
                    commentsCount: photo.map { $0.comments?.count ?? 0 } ?? 0,
                    isLiked: photo.map { photoLikedOverrides[$0.id] ?? ($0.likes?.userLikes == 1) } ?? false,
                    onLike: photo.map { p in
                        photoLikeInProgress.contains(p.id) ? nil : { likeTogglePhoto(photoId: p.id) }
                    } ?? nil,
                    photoCommentsContext: photo.map { PhotoCommentsContext(ownerId: ownerId, photoId: $0.id) },
                    authService: authService,
                    photoIdsForSaving: photos.map { (ownerId, $0.id) },
                    onAddToSaved: { oid, pid in
                        guard let token = authService.accessToken else { return false }
                        do {
                            _ = try await vkApi.photosCopy(token: token, ownerId: oid, photoId: pid)
                            return true
                        } catch { return false }
                    }
                )
            }
        }
        .onAppear { loadPhotos(offset: 0, append: false) }
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

    private func loadPhotos(offset: Int, append: Bool) {
        guard let token = authService.accessToken else { return }
        if append {
            loadMoreState = .loading
        } else {
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
                    else { loadState = .failed(error) }
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
