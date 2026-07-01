import SwiftUI
import Photos
import UIKit

/// Один URL — на весь экран. Zoom: двойной тап или pinch (UIScrollView). При scale > 1 — пан по картинке. Если onTap задан — одиночный тап переключает панель; иначе тап закрывает.
struct FullScreenImageView: View {
    let imageURL: URL?
    let onDismiss: () -> Void
    var onTap: (() -> Void)? = nil
    var onScaleChange: ((CGFloat) -> Void)? = nil
    var onSwipeDown: (() -> Void)? = nil

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = imageURL {
                ZoomableScrollView(
                    url: url,
                    onSingleTap: { [onTap, onDismiss] in onTap != nil ? onTap!() : onDismiss() },
                    onScaleChange: { newScale in
                        scale = newScale
                        onScaleChange?(newScale)
                    },
                    onSwipeDown: onSwipeDown
                )
                .onAppear { onScaleChange?(1.0) }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - UIScrollView-based zoom (pinch, double-tap, pan, swipe-down)

private struct ZoomableScrollView: UIViewRepresentable {
    let url: URL
    let onSingleTap: () -> Void
    let onScaleChange: ((CGFloat) -> Void)?
    let onSwipeDown: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap, onScaleChange: onScaleChange, onSwipeDown: onSwipeDown)
    }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        scrollView.panGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.handlePan(_:)))

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onScaleChange = onScaleChange
        context.coordinator.onSwipeDown = onSwipeDown
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            context.coordinator.loadImage(url: url)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: () -> Void
        var onScaleChange: ((CGFloat) -> Void)?
        var onSwipeDown: (() -> Void)?
        var currentURL: URL?
        weak var imageView: UIImageView?
        weak var scrollView: ZoomScrollView?

        init(onSingleTap: @escaping () -> Void, onScaleChange: ((CGFloat) -> Void)?, onSwipeDown: (() -> Void)?) {
            self.onSingleTap = onSingleTap
            self.onScaleChange = onScaleChange
            self.onSwipeDown = onSwipeDown
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            onScaleChange?(scrollView.zoomScale)
        }

        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        func loadImage(url: URL) {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            scrollView.setZoomScale(1.0, animated: false)
            imageView.image = nil
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard let self = self,
                          let imageView = self.imageView,
                          let scrollView = self.scrollView else { return }
                    imageView.image = image
                    self.setImageFrame(scrollView: scrollView, image: image)
                    self.onScaleChange?(1.0)
                }
            }.resume()
        }

        func setImageFrame(scrollView: UIScrollView, image: UIImage) {
            guard let imageView = imageView else { return }
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let aspect = image.size.width / image.size.height
            let scrollAspect = size.width / size.height
            let w: CGFloat, h: CGFloat
            if aspect > scrollAspect { w = size.width; h = w / aspect }
            else { h = size.height; w = h * aspect }
            imageView.frame = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            scrollView.contentSize = CGSize(width: w, height: h)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                guard let imageView = imageView else { return }
                let location = recognizer.location(in: imageView)
                let zoomScale: CGFloat = 2.5
                let w = scrollView.bounds.width / zoomScale
                let h = scrollView.bounds.height / zoomScale
                scrollView.zoom(to: CGRect(x: location.x - w / 2, y: location.y - h / 2, width: w, height: h), animated: true)
            }
        }

        @objc func handleSingleTap() {
            DispatchQueue.main.async { self.onSingleTap() }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = scrollView, scrollView.zoomScale <= 1.0 else { return }
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: scrollView)
            let velocity = recognizer.velocity(in: scrollView)
            if translation.y > 60 && velocity.y > 80 && abs(translation.y) > abs(translation.x) {
                DispatchQueue.main.async { self.onSwipeDown?() }
            }
        }
    }
}

/// UIScrollView, не перехватывающий горизонтальные свайпы при zoom == 1 (чтобы TabView мог листать страницы).
private class ZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        if zoomScale > 1.0 { return true }
        let t = pan.translation(in: self)
        if t == .zero { return false }
        return abs(t.y) > abs(t.x)
    }
}

// MARK: - Идентификатор фото для сохранения (photos.copy)

/// owner_id, photo_id и опционально access_key для «Добавить в сохранённые».
struct PhotoSaveId: Hashable {
    let ownerId: Int
    let photoId: Int
    let accessKey: String?
}

// MARK: - Контейнер photoId для обхода ABI-бага

/// Разделяемый ref-type контейнер для передачи photoId в onDeletePhoto.
/// Обходит баг Swift ARM64 ABI: при вызове @escaping async замыкания с (String, Int, Int)
/// String занимает 2 регистра, и оба Int-аргумента смещаются в регистры async-контекста.
/// Решение: gallery записывает photoId в этот объект синхронно ДО await, closure читает из него.
final class GalleryDeleteRequest {
    var photoId: Int = 0
}

// MARK: - Галерея с пролистыванием (пост / альбом)

/// Несколько фото на весь экран: PageView, панель по тапу (лайк, комментарии, 3 точки), закрытие — кнопка или свайп вниз.
/// Если передан postCommentsContext или photoCommentsContext + authService — sheet комментариев показывается из галереи (поверх fullscreen).
struct FullScreenPhotoGalleryView: View {
    let urls: [URL]
    let initialIndex: Int
    let onDismiss: () -> Void
    /// Счётчики для отображения на панели (из поста); nil — не показывать число.
    var likesCount: Int? = nil
    var commentsCount: Int? = nil
    var repostsCount: Int? = nil
    /// Лайк и комментарии: при вызове из поста — те же действия, что под постом.
    var isLiked: Bool = false
    var onLike: (() -> Void)? = nil
    var onTapComments: (() -> Void)? = nil
    /// Контекст комментариев к посту — sheet показывается из галереи, поверх fullscreen.
    var postCommentsContext: PostCommentsContext? = nil
    /// Контекст комментариев к фото (альбом) — sheet показывается из галереи.
    var photoCommentsContext: PhotoCommentsContext? = nil
    var authService: AuthService? = nil
    /// Для «Добавить в сохранённые»: массив в том же порядке, что и urls. nil — пункт скрыт/неактивен.
    var photoIdsForSaving: [PhotoSaveId]? = nil
    /// VK API для «Добавить в сохранённые» — галерея сама вызывает photosCopy (без closure, чтобы избежать EXC_BAD_ACCESS).
    var vkApi: VKApiService? = nil
    /// Опционально: возврат токена для «Удалить» / «Сделать фото профиля».
    var getAccessToken: (() -> String)? = nil
    /// true = альбом «Сохранённые»: пункт «Добавить в сохранённые» не показываем (VK не даёт копировать из него снова).
    var isSavedAlbum: Bool = false
    /// Токен на момент открытия галереи (для «Удалить» / «Сделать фото профиля» в fullScreenCover).
    var initialAccessToken: String = ""
    /// true = фото свои (владелец = текущий пользователь): показывать «Удалить», не показывать «Добавить в сохранённые».
    var isOwnPhotos: Bool = false
    /// Удалить текущее фото (token, ownerId, photoId). Возвращает true при успехе. nil = пункт не показывать.
    var onDeletePhoto: ((String, Int, Int) async -> Bool)? = nil
    /// true = альбом «Фото профиля» (-6): показывать пункт «Сделать фото профиля» для своих фото.
    var isProfileAlbum: Bool = false
    /// Сделать текущее фото главным в профиле (photos.makeCover). Возвращает (успех, сообщение об ошибке). nil = пункт не показывать.
    var onMakeProfilePhoto: ((String, Int, Int) async -> (Bool, String?))? = nil
    /// Для репоста из галереи поста: object = "wall{owner_id}_{post_id}". nil = кнопка репоста неактивна/заглушка.
    var repostObject: String? = nil
    /// После успешного wall.repost вызывается с новым reposts_count (чтобы обновить счётчик в ленте).
    var onRepostSuccess: ((Int) -> Void)? = nil
    /// Shared-объект для передачи photoId в onDeletePhoto в обход ABI-бага. nil = не используется.
    var galleryDeleteRequest: GalleryDeleteRequest? = nil

    @State private var currentIndex: Int
    @State private var overlayVisible = true
    @State private var showActionsSheet = false
    @State private var showRepostSheet = false
    @State private var addToSavedInProgress = false
    @State private var addToSavedDone = false
    @State private var addToSavedFailed = false
    /// Показать тост «Фото добавлено в «Сохранённые»» после успешного сохранения.
    @State private var showSavedToast = false
    /// Показать тост «Не удалось сохранить» при ошибке.
    @State private var showFailedToast = false
    /// Локальное переопределение после тапа «Нравится» до закрытия галереи.
    @State private var likedOverride: Bool? = nil
    @State private var presentedPostComments: PostCommentsContext? = nil
    @State private var presentedPhotoComments: PhotoCommentsContext? = nil
    /// Показать панель действий (вместо Menu — избегаем _UIReparentingView в fullScreenCover).
    @State private var showActionsOverlay = false
    /// Для своих фото используем нативный confirmationDialog, чтобы не ловить проблемы hit-testing в custom overlay.
    @State private var showOwnPhotoActionsDialog = false
    /// Токен, захваченный при открытии панели «три точки» — чтобы в fullScreenCover не терять.
    @State private var capturedTokenForSave: String = ""
    @State private var deletePhotoInProgress = false
    @State private var showDeleteActionErrorToast = false
    @State private var deleteActionErrorText: String = ""
    @State private var makeProfilePhotoInProgress = false
    @State private var showMakeProfileSuccessToast = false
    @State private var showMakeProfileErrorToast = false
    @State private var makeProfileErrorText: String = ""
    @State private var saveToDeviceInProgress = false
    @State private var showSaveToDeviceToast = false
    @State private var saveToDeviceSuccess = true
    @State private var shareFileURL: URL? = nil
    @State private var showShareSheet = false
    @State private var shareInProgress = false
    /// Локальный счётчик репостов после успешного wall.repost в галерее.
    @State private var repostsCountOverride: Int? = nil
    @State private var repostInProgress = false
    @State private var showRepostSuccessToast = false
    /// Масштаб текущей страницы: при > 1 не листаем (пан по картинке).
    @State private var currentPageZoomScale: CGFloat = 1

    init(
        urls: [URL],
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        likesCount: Int? = nil,
        commentsCount: Int? = nil,
        repostsCount: Int? = nil,
        isLiked: Bool = false,
        onLike: (() -> Void)? = nil,
        onTapComments: (() -> Void)? = nil,
        postCommentsContext: PostCommentsContext? = nil,
        photoCommentsContext: PhotoCommentsContext? = nil,
        authService: AuthService? = nil,
        photoIdsForSaving: [PhotoSaveId]? = nil,
        vkApi: VKApiService? = nil,
        getAccessToken: (() -> String)? = nil,
        isSavedAlbum: Bool = false,
        initialAccessToken: String = "",
        isOwnPhotos: Bool = false,
        onDeletePhoto: ((String, Int, Int) async -> Bool)? = nil,
        isProfileAlbum: Bool = false,
        onMakeProfilePhoto: ((String, Int, Int) async -> (Bool, String?))? = nil,
        repostObject: String? = nil,
        onRepostSuccess: ((Int) -> Void)? = nil,
        galleryDeleteRequest: GalleryDeleteRequest? = nil
    ) {
        self.urls = urls
        self.initialIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        self.onDismiss = onDismiss
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.repostsCount = repostsCount
        self.isLiked = isLiked
        self.onLike = onLike
        self.onTapComments = onTapComments
        self.postCommentsContext = postCommentsContext
        self.photoCommentsContext = photoCommentsContext
        self.authService = authService
        self.photoIdsForSaving = photoIdsForSaving
        self.vkApi = vkApi
        self.getAccessToken = getAccessToken
        self.isSavedAlbum = isSavedAlbum
        self.initialAccessToken = initialAccessToken
        self.isOwnPhotos = isOwnPhotos
        self.onDeletePhoto = onDeletePhoto
        self.isProfileAlbum = isProfileAlbum
        self.onMakeProfilePhoto = onMakeProfilePhoto
        self.repostObject = repostObject
        self.onRepostSuccess = onRepostSuccess
        self.galleryDeleteRequest = galleryDeleteRequest
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
        _capturedTokenForSave = State(initialValue: initialAccessToken)
    }

    private var displayLiked: Bool { likedOverride ?? isLiked }
    private var displayRepostsCount: Int { repostsCountOverride ?? repostsCount ?? 0 }
    private var displayLikesCount: Int {
        guard let n = likesCount else { return 0 }
        if likedOverride == true, !isLiked { return n + 1 }
        if likedOverride == false, isLiked { return max(0, n - 1) }
        return n
    }

    private var pagingTabView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                FullScreenImageView(
                    imageURL: url,
                    onDismiss: onDismiss,
                    onTap: { overlayVisible.toggle() },
                    onScaleChange: { newScale in
                        if index == currentIndex {
                            currentPageZoomScale = newScale
                        }
                    },
                    onSwipeDown: onDismiss
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if urls.isEmpty {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.5))
                    .onTapGesture(perform: onDismiss)
            } else {
                // Структура вью не меняется при zoom — включаем/выключаем жест через .including,
                // иначе SwiftUI пересоздаёт TabView и AsyncImage перезагружается.
                pagingTabView
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0).onChanged { _ in },
                        including: .none
                    )
                .onChange(of: currentIndex) { _, _ in
                    currentPageZoomScale = 1
                }

                if overlayVisible {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)
                        bottomBar
                    }
                    .transition(.opacity)
                }

                if showSavedToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Фото добавлено в «Сохранённые»")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
                }
                if showFailedToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Не удалось сохранить")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                if showRepostSuccessToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Репост выполнен")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                if showMakeProfileSuccessToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text("Фото установлено как главное в профиле")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                if showMakeProfileErrorToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text(makeProfileErrorText)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                if showDeleteActionErrorToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text(deleteActionErrorText)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                if showSaveToDeviceToast {
                    VStack {
                        Spacer(minLength: 0)
                        Text(saveToDeviceSuccess ? "Фото сохранено в «Фото»" : "Не удалось сохранить в «Фото»")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .zIndex(2)
                }

                // Стрелки влево/вправо — почти прозрачные, перелистывание
                if urls.count > 1 {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentIndex = max(0, currentIndex - 1)
                            }
                        } label: {
                            Color.clear
                                .frame(width: 56, height: 120)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex <= 0)
                        .padding(.leading, 4)

                        Spacer(minLength: 0)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentIndex = min(urls.count - 1, currentIndex + 1)
                            }
                        } label: {
                            Color.clear
                                .frame(width: 56, height: 120)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex >= urls.count - 1)
                        .padding(.trailing, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                }
            }
        }
        .onAppear {
            currentIndex = initialIndex
            if !initialAccessToken.isEmpty { capturedTokenForSave = initialAccessToken }
        }
        .sheet(item: $presentedPostComments) { ctx in
            if let auth = authService {
                PostCommentsView(context: ctx, authService: auth)
            }
        }
        .sheet(item: $presentedPhotoComments) { ctx in
            if let auth = authService {
                PhotoCommentsView(context: ctx, authService: auth)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            if let u = shareFileURL { try? FileManager.default.removeItem(at: u) }
            shareFileURL = nil
        }) {
            if let u = shareFileURL {
                ShareSheet(activityItems: [u])
            }
        }
        .confirmationDialog("", isPresented: $showActionsSheet, titleVisibility: .hidden) {
            Button(shareInProgress ? "Загрузка…" : "Отправить в …") { shareCurrentPhoto() }
                .disabled(shareInProgress)
            Button(saveToDeviceInProgress ? "Сохранение…" : "Скачать на устройство") { saveCurrentPhotoToDevice() }
                .disabled(saveToDeviceInProgress)
            Button("Отмена", role: .cancel) { }
        }
        .confirmationDialog("Поделиться", isPresented: $showRepostSheet) {
            Button("На мою страницу") { performRepost() }
            Button("Отправить в сообщениях") { }
            Button("Отмена", role: .cancel) { }
        }
        .confirmationDialog("", isPresented: $showOwnPhotoActionsDialog, titleVisibility: .hidden) {
            if isProfileAlbum, let makeProfile = onMakeProfilePhoto, let ids = photoIdsForSaving, currentIndex < ids.count {
                Button(makeProfilePhotoInProgress ? "Сохранение…" : "Сделать фото профиля") {
                    performMakeProfilePhoto(makeProfile: makeProfile, ids: ids)
                }
                .disabled(makeProfilePhotoInProgress)
            }
            if let deletePhoto = onDeletePhoto, let ids = photoIdsForSaving, currentIndex < ids.count {
                Button(deletePhotoInProgress ? "Удаление…" : "Удалить", role: .destructive) {
                    performDeleteCurrentPhoto(deletePhoto: deletePhoto, ids: ids)
                }
                .disabled(deletePhotoInProgress)
            }
            Button(saveToDeviceInProgress ? "Сохранение…" : "Скачать на устройство") {
                saveCurrentPhotoToDevice()
            }
            .disabled(saveToDeviceInProgress)
            Button(shareInProgress ? "Загрузка…" : "Отправить в …") {
                shareCurrentPhoto()
            }
            .disabled(shareInProgress)
            Button("Отмена", role: .cancel) { }
        }
        .onChange(of: showOwnPhotoActionsDialog) { _, newValue in
            let idsCount = photoIdsForSaving?.count ?? 0
            AppLogger.shared.info(
                "Gallery",
                "own actions dialog changed visible=\(newValue) currentIndex=\(currentIndex) idsCount=\(idsCount) hasDelete=\(onDeletePhoto != nil)"
            )
        }
    }

    /// Репост поста на свою стену (wall.repost). Вызывается из нижней панели при repostObject != nil.
    private func performRepost() {
        guard let object = repostObject, !object.isEmpty, let api = vkApi else { return }
        let token = getAccessToken?() ?? authService?.accessToken ?? capturedTokenForSave
        guard !token.isEmpty, !repostInProgress else { return }
        repostInProgress = true
        Task {
            do {
                let response = try await api.wallRepost(token: token, object: object)
                await MainActor.run {
                    repostInProgress = false
                    if let newCount = response.repostsCount {
                        repostsCountOverride = newCount
                        onRepostSuccess?(newCount)
                        showRepostSuccessToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showRepostSuccessToast = false
                        }
                    }
                }
            } catch {
                AppLogger.shared.error("Gallery", "wall.repost failed", error: error)
                await MainActor.run { repostInProgress = false }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { onDismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(currentIndex + 1) из \(urls.count)")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            Button { showActionsSheet = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.top, 8)
        .background(Color.black.opacity(0.45).ignoresSafeArea(edges: .top))
    }

    private func resolveActionToken(preferCaptured: Bool = false) -> String {
        let liveToken = getAccessToken?() ?? authService?.accessToken ?? ""
        if preferCaptured {
            if !capturedTokenForSave.isEmpty { return capturedTokenForSave }
            if !liveToken.isEmpty { return liveToken }
            return initialAccessToken
        }
        if !liveToken.isEmpty { return liveToken }
        if !capturedTokenForSave.isEmpty { return capturedTokenForSave }
        return initialAccessToken
    }

    private func presentDeleteActionError(_ text: String) {
        deleteActionErrorText = text
        showDeleteActionErrorToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showDeleteActionErrorToast = false
        }
    }

    private func performDeleteCurrentPhoto(
        deletePhoto: @escaping (String, Int, Int) async -> Bool,
        ids: [PhotoSaveId]
    ) {
        AppLogger.shared.info(
            "Gallery",
            "performDeleteCurrentPhoto invoked currentIndex=\(currentIndex) idsCount=\(ids.count) overlayVisible=\(overlayVisible)"
        )
        guard currentIndex < ids.count else {
            AppLogger.shared.error("Gallery", "delete aborted: currentIndex out of bounds currentIndex=\(currentIndex) idsCount=\(ids.count)")
            presentDeleteActionError("Не удалось определить текущее фото")
            return
        }
        let item = ids[currentIndex]
        // Явно извлекаем Int-значения ДО Task — обход бага Swift ABI при передаче Int
        // через @escaping async-замыкание: значения повреждаются если обращаться к item
        // внутри await-выражения.
        let photoIdToDelete: Int = item.photoId
        let ownerIdToDelete: Int = item.ownerId
        let token = resolveActionToken(preferCaptured: true)
        AppLogger.shared.info(
            "Gallery",
            "delete action tapped photoId=\(photoIdToDelete) ownerId=\(ownerIdToDelete) tokenEmpty=\(token.isEmpty) inProgress=\(deletePhotoInProgress)"
        )
        guard !token.isEmpty else {
            presentDeleteActionError("Войдите в аккаунт снова")
            return
        }
        guard !deletePhotoInProgress else { return }
        deletePhotoInProgress = true
        showActionsOverlay = false
        showOwnPhotoActionsDialog = false
        // Передаём photoId через shared object до await — обход ABI-бага Swift на ARM64.
        galleryDeleteRequest?.photoId = photoIdToDelete
        Task {
            AppLogger.shared.info("Gallery", "delete action started photoId=\(photoIdToDelete)")
            // Вторые и третьи Int-аргументы игнорируются в onDelete-замыкании AlbumPhotosView
            // (замыкание читает photoId из galleryDeleteRequest). Для совместимости с другими
            // вызывающими (PostCellView и т.д.) передаём реальные значения — там замыкание
            // по-прежнему использует параметр.
            let ok = await deletePhoto(token, ownerIdToDelete, photoIdToDelete)
            await MainActor.run {
                deletePhotoInProgress = false
                // Всегда закрываем галерею: при ok=true – успех, при ok=false – ошибка уже
                // показана тостом внутри галереи через deletePhotoFromAlbum, и мы уходим
                // чтобы не оставлять пользователя в залипшем состоянии.
                onDismiss()
            }
        }
    }

    private func performMakeProfilePhoto(
        makeProfile: @escaping (String, Int, Int) async -> (Bool, String?),
        ids: [PhotoSaveId]
    ) {
        guard currentIndex < ids.count else { return }
        let item = ids[currentIndex]
        let token = resolveActionToken()
        guard !token.isEmpty, !makeProfilePhotoInProgress else {
            showActionsOverlay = false
            showOwnPhotoActionsDialog = false
            if token.isEmpty {
                makeProfileErrorText = "Войдите в аккаунт снова"
                showMakeProfileErrorToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showMakeProfileErrorToast = false }
            }
            return
        }
        makeProfilePhotoInProgress = true
        showActionsOverlay = false
        showOwnPhotoActionsDialog = false
        Task {
            let (ok, errorMessage) = await makeProfile(token, item.ownerId, item.photoId)
            await MainActor.run {
                makeProfilePhotoInProgress = false
                if ok {
                    showMakeProfileSuccessToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showMakeProfileSuccessToast = false
                    }
                } else {
                    makeProfileErrorText = errorMessage ?? "Не удалось установить фото профиля"
                    showMakeProfileErrorToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showMakeProfileErrorToast = false
                    }
                }
            }
        }
    }

    /// Иконка и счётчик под ней (для лайков, комментов, репостов в нижней панели).
    private func bottomBarIconWithCount(icon: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
            Text("\(count)")
                .font(.caption2)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Group {
                if let action = onLike {
                    Button {
                        likedOverride = !displayLiked
                        action()
                    } label: {
                        bottomBarIconWithCount(icon: displayLiked ? "heart.fill" : "heart", count: displayLikesCount)
                    }
                    .foregroundStyle(displayLiked ? .red : .white)
                    .buttonStyle(.plain)
                } else {
                    bottomBarIconWithCount(icon: "heart", count: likesCount ?? 0)
                        .foregroundStyle(.white)
                }
            }
            .font(.title2)
            .frame(width: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            Group {
                if postCommentsContext != nil || photoCommentsContext != nil || onTapComments != nil {
                    Button {
                        if let ctx = postCommentsContext, authService != nil {
                            presentedPostComments = ctx
                        } else if let ctx = photoCommentsContext, authService != nil {
                            presentedPhotoComments = ctx
                        } else {
                            onTapComments?()
                        }
                    } label: {
                        bottomBarIconWithCount(icon: "bubble.right", count: commentsCount ?? 0)
                    }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                } else {
                    bottomBarIconWithCount(icon: "bubble.right", count: commentsCount ?? 0)
                        .foregroundStyle(.white)
                }
            }
            .font(.title2)
            .frame(maxWidth: .infinity)

            Button {
                if repostObject != nil { showRepostSheet = true }
            } label: {
                if repostInProgress {
                    ProgressView().tint(.white)
                } else {
                    bottomBarIconWithCount(icon: "arrowshape.turn.up.right", count: displayRepostsCount)
                }
            }
            .font(.title2)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .disabled(repostInProgress || repostObject == nil)
            .frame(width: 44)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 16)
        .padding(.bottom, 24)
        .background(Color.black.opacity(0.5))
    }

    /// Поделиться фото в другие приложения (share sheet). Скачивает изображение во временный файл, затем показывает UIActivityViewController.
    private func shareCurrentPhoto() {
        guard currentIndex >= 0, currentIndex < urls.count else { return }
        let url = urls[currentIndex]
        shareInProgress = true
        Task { @MainActor in
            let fileURL = await prepareImageFileForSharing(url: url)
            shareInProgress = false
            if let fileURL {
                shareFileURL = fileURL
                showShareSheet = true
            }
        }
    }

    /// Скачать текущее фото по URL и сохранить в «Фото». Требуется NSPhotoLibraryAddUsageDescription в Info.
    private func saveCurrentPhotoToDevice() {
        guard currentIndex >= 0, currentIndex < urls.count else { return }
        let url = urls[currentIndex]
        saveToDeviceInProgress = true
        showActionsOverlay = false
        Task { @MainActor in
            let success = await saveImageToPhotoLibrary(url: url)
            saveToDeviceInProgress = false
            saveToDeviceSuccess = success
            showSaveToDeviceToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                showSaveToDeviceToast = false
            }
        }
    }
}

// MARK: - Share sheet (UIActivityViewController)

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Скачивает изображение по URL и сохраняет во временный файл для share sheet. Вызывающий обязан удалить файл после использования.
private func prepareImageFileForSharing(url: URL) async -> URL? {
    guard let (data, _) = try? await URLSession.shared.data(from: url),
          !data.isEmpty,
          UIImage(data: data) != nil else { return nil }
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".jpg", isDirectory: false)
    do {
        try data.write(to: tempFile)
        return tempFile
    } catch {
        return nil
    }
}

// MARK: - Сохранение изображения в «Фото»

/// Сохраняет изображение по URL в альбом «Фото». Используется запись во временный файл и creationRequestForAssetFromImage(atFileURL:) — без UIImage в фоновом потоке, чтобы избежать краша.
/// В Target → Info нужен ключ NSPhotoLibraryAddUsageDescription (например: «Сохранение фото в галерею»).
private func saveImageToPhotoLibrary(url: URL) async -> Bool {
    let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                cont.resume(returning: status)
            }
        }
    }
    guard status == .authorized || status == .limited else { return false }
    guard let (data, _) = try? await URLSession.shared.data(from: url),
          !data.isEmpty,
          UIImage(data: data) != nil else { return false }
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".jpg", isDirectory: false)
    do {
        try data.write(to: tempFile)
    } catch {
        return false
    }
    return await withCheckedContinuation { cont in
        let fileURL = tempFile
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }) { success, _ in
            DispatchQueue.main.async {
                cont.resume(returning: success)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
