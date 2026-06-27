import SwiftUI

/// Материалы диалога: вкладки Фото | Видео | Поиск. Пагинация: первая загрузка 200 сообщений, подгрузка по 150.
struct DialogMaterialsView: View {
    let peerId: Int
    @ObservedObject var authService: AuthService
    let vkApi: VKApiService

    @Environment(\.dismiss) private var dismiss

    // Загрузка истории: 200 при открытии, затем по 150 по кнопке.
    @State private var loadedMessages: [VKMessage] = []
    @State private var totalMessagesCount: Int = 0
    @State private var materialsLoadState: MaterialsLoadState = .idle
    @State private var isLoadingMore = false

    // Поиск (вкладка «Поиск»).
    @State private var searchQuery: String = ""
    @State private var searchResults: [VKMessage] = []
    @State private var searchLoading = false
    @State private var searchError: String?

    // Галерея фото (fullscreen).
    @State private var showGallery = false
    @State private var galleryPhotos: [VKPhoto] = []
    @State private var galleryIndex: Int = 0

    private let initialPageSize = 200
    private let nextPageSize = 150

    enum MaterialsLoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    private var allPhotos: [VKPhoto] {
        loadedMessages.flatMap { msg in (msg.attachments ?? []).compactMap(\.photo) }
    }

    private var allVideos: [VKVideo] {
        loadedMessages.flatMap { msg in (msg.attachments ?? []).compactMap(\.video) }
    }

    /// Уникальный id для ячейки фото (чтобы при подгрузке старых не ломать сетку).
    private var photoItems: [(id: String, photo: VKPhoto, index: Int)] {
        allPhotos.enumerated().map { idx, p in
            ("\(p.ownerId ?? 0)_\(p.id)_\(idx)", p, idx)
        }
    }

    var body: some View {
        NavigationStack {
            TabView {
                photosTabContent
                    .tabItem {
                        Label("Фото", systemImage: "photo.on.rectangle.angled")
                    }

                videosTabContent
                    .tabItem {
                        Label("Видео", systemImage: "video.fill")
                    }

                searchTabContent
                    .tabItem {
                        Label("Поиск", systemImage: "magnifyingglass")
                    }
            }
            .navigationTitle("Материалы диалога")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showGallery) {
                let urls = galleryPhotos.compactMap { URL(string: $0.displayURL ?? "") }
                let saveIds = galleryPhotos.compactMap { p -> PhotoSaveId? in
                    guard let ownerId = p.ownerId else { return nil }
                    return PhotoSaveId(ownerId: ownerId, photoId: p.id, accessKey: p.accessKey)
                }
                FullScreenPhotoGalleryView(
                    urls: urls,
                    initialIndex: galleryIndex,
                    onDismiss: { showGallery = false },
                    photoIdsForSaving: saveIds,
                    vkApi: vkApi,
                    getAccessToken: { authService.accessToken ?? "" }
                )
            }
        }
        .onAppear {
            if loadedMessages.isEmpty, case .idle = materialsLoadState {
                loadInitialHistory()
            }
        }
    }

    // MARK: - Вкладка «Фото»

    private var photosTabContent: some View {
        Group {
            switch materialsLoadState {
            case .idle, .loading:
                VStack {
                    Spacer()
                    ProgressView("Загрузка материалов…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if allPhotos.isEmpty {
                    ContentUnavailableView(
                        "Нет фото",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("В загруженных сообщениях пока нет фото.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                                ForEach(photoItems, id: \.id) { item in
                                    photoThumb(item.photo, index: item.index)
                                }
                            }

                            if loadedMessages.count < totalMessagesCount && !isLoadingMore {
                                loadMoreButton
                            } else if isLoadingMore {
                                ProgressView("Подгрузка…")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .padding()
                    }
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка загрузки",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Вкладка «Видео»

    private var videosTabContent: some View {
        Group {
            switch materialsLoadState {
            case .idle, .loading:
                VStack {
                    Spacer()
                    ProgressView("Загрузка материалов…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if allVideos.isEmpty {
                    ContentUnavailableView(
                        "Нет видео",
                        systemImage: "video.fill",
                        description: Text("В загруженных сообщениях пока нет видео.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(allVideos.enumerated()), id: \.offset) { _, video in
                                videoRow(video)
                            }
                            if loadedMessages.count < totalMessagesCount && !isLoadingMore {
                                loadMoreButton
                            } else if isLoadingMore {
                                ProgressView("Подгрузка…")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .padding()
                    }
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка загрузки",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            loadMoreHistory()
        } label: {
            Text("Подгрузить ещё")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }

    // MARK: - Вкладка «Поиск»

    private var searchTabContent: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Текст для поиска", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("Искать") {
                        performSearch()
                    }
                    .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || searchLoading)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            if searchLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            if let err = searchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            ForEach(searchResults, id: \.id) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    Text(msg.text.isEmpty ? "[Вложение]" : msg.text)
                        .font(.body)
                        .lineLimit(3)
                    Text(shortDate(msg.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Загрузка истории (200 при открытии, по 150 по кнопке)

    private func loadInitialHistory() {
        guard let token = authService.accessToken else {
            materialsLoadState = .failed(VKApiError.missingToken)
            return
        }
        materialsLoadState = .loading
        Task {
            do {
                let res = try await vkApi.getHistory(token: token, peerId: peerId, count: initialPageSize, offset: 0)
                await MainActor.run {
                    loadedMessages = res.items.reversed()
                    totalMessagesCount = res.count
                    materialsLoadState = .loaded
                }
            } catch {
                await MainActor.run {
                    materialsLoadState = .failed(error)
                }
            }
        }
    }

    private func loadMoreHistory() {
        guard let token = authService.accessToken else { return }
        guard loadedMessages.count < totalMessagesCount, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = loadedMessages.count
        Task {
            do {
                let res = try await vkApi.getHistory(token: token, peerId: peerId, count: nextPageSize, offset: offset)
                await MainActor.run {
                    let older = res.items.reversed()
                    loadedMessages = loadedMessages + older
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }

    // MARK: - UI компоненты

    private func photoThumb(_ photo: VKPhoto, index: Int) -> some View {
        let thumbUrl = photo.feedPreviewURL.flatMap { URL(string: $0) }
        return AsyncImage(url: thumbUrl) { phase in
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
        .frame(width: 100, height: 100)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            galleryPhotos = allPhotos
            galleryIndex = index
            showGallery = true
        }
    }

    private func videoRow(_ video: VKVideo) -> some View {
        let thumbUrl = video.previewImageURL.flatMap { URL(string: $0) }
        return HStack(spacing: 12) {
            AsyncImage(url: thumbUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "video").resizable().scaledToFit().foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 80, height: 60)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title ?? "Видео")
                    .font(.subheadline)
                    .lineLimit(2)
                if let d = video.duration {
                    Text(formatDuration(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let token = authService.accessToken else { return }
        searchError = nil
        searchLoading = true
        Task {
            do {
                let res = try await vkApi.searchMessages(token: token, peerId: peerId, q: q, count: 50)
                await MainActor.run {
                    searchResults = res.items.reversed()
                    searchLoading = false
                }
            } catch {
                await MainActor.run {
                    searchError = error.localizedDescription
                    searchLoading = false
                }
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
