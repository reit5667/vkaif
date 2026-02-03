import SwiftUI

/// Фото альбома (photos.get): сетка, тап — полноэкран.
struct AlbumPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService: AuthService
    let ownerId: Int
    let albumId: Int
    let albumTitle: String

    @State private var photos: [VKPhoto] = []
    @State private var loadState: AlbumPhotosLoadState = .idle
    @State private var fullScreenInitialIndex: Int = 0
    @State private var isFullScreenPresented = false

    private let vkApi = VKApiService()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

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
                            ForEach(Array(photos.enumerated()), id: \.element.id) { _, photo in
                                photoCell(photo)
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
        .fullScreenCover(isPresented: $isFullScreenPresented) {
            let urls = photos.compactMap { $0.displayURL }.compactMap { URL(string: $0) }
            if !urls.isEmpty {
                FullScreenPhotoGalleryView(
                    urls: urls,
                    initialIndex: min(fullScreenInitialIndex, urls.count - 1),
                    onDismiss: { isFullScreenPresented = false }
                )
            }
        }
        .onAppear { loadPhotos() }
    }

    private func photoCell(_ photo: VKPhoto) -> some View {
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
            if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
                fullScreenInitialIndex = idx
                isFullScreenPresented = true
            }
        }
    }

    private func loadPhotos() {
        guard let token = authService.accessToken else { return }
        loadState = .loading
        Task {
            do {
                let response = try await vkApi.getPhotos(token: token, ownerId: ownerId, albumId: albumId)
                await MainActor.run {
                    photos = response.items
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }
}

enum AlbumPhotosLoadState {
    case idle
    case loading
    case loaded
    case failed(Error)
}
