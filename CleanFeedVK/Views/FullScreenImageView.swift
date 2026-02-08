import SwiftUI

/// Один URL — на весь экран. Если onTap задан — тап переключает панель; иначе тап закрывает.
struct FullScreenImageView: View {
    let imageURL: URL?
    let onDismiss: () -> Void
    /// Если задан — по тапу вызывается onTap (галерея: показать панель); иначе тап = onDismiss.
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white.opacity(0.5))
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            } else {
                onDismiss()
            }
        }
    }
}

// MARK: - Идентификатор фото для сохранения (photos.copy)

/// owner_id, photo_id и опционально access_key для «Добавить в сохранённые».
struct PhotoSaveId: Hashable {
    let ownerId: Int
    let photoId: Int
    let accessKey: String?
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
    /// Вызов при тапе «Добавить в сохранённые». (token, ownerId, photoId, accessKey). Возвращает true при успехе.
    var onAddToSaved: ((String, Int, Int, String?) async -> Bool)? = nil
    /// Опционально: возврат токена при тапе «Добавить в сохранённые» (надёжнее в fullScreenCover).
    var getAccessToken: (() -> String)? = nil
    /// true = альбом «Сохранённые»: пункт «Добавить в сохранённые» не показываем (VK не даёт копировать из него снова).
    var isSavedAlbum: Bool = false
    /// Токен на момент открытия галереи (в fullScreenCover getAccessToken часто пуст — передаём сюда при показе).
    var initialAccessToken: String = ""
    /// true = фото свои (владелец = текущий пользователь): показывать «Удалить», не показывать «Добавить в сохранённые».
    var isOwnPhotos: Bool = false
    /// Удалить текущее фото (token, ownerId, photoId). Возвращает true при успехе. nil = пункт не показывать.
    var onDeletePhoto: ((String, Int, Int) async -> Bool)? = nil
    /// true = альбом «Фото профиля» (-6): показывать пункт «Сделать фото профиля» для своих фото.
    var isProfileAlbum: Bool = false
    /// Сделать текущее фото главным в профиле (photos.makeCover). Возвращает (успех, сообщение об ошибке). nil = пункт не показывать.
    var onMakeProfilePhoto: ((String, Int, Int) async -> (Bool, String?))? = nil

    @State private var currentIndex: Int
    @State private var overlayVisible = false
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
    /// Токен, захваченный при открытии панели «три точки» — чтобы в fullScreenCover не терять.
    @State private var capturedTokenForSave: String = ""
    @State private var deletePhotoInProgress = false
    @State private var makeProfilePhotoInProgress = false
    @State private var showMakeProfileSuccessToast = false
    @State private var showMakeProfileErrorToast = false
    @State private var makeProfileErrorText: String = ""

    init(
        urls: [URL],
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        likesCount: Int? = nil,
        commentsCount: Int? = nil,
        isLiked: Bool = false,
        onLike: (() -> Void)? = nil,
        onTapComments: (() -> Void)? = nil,
        postCommentsContext: PostCommentsContext? = nil,
        photoCommentsContext: PhotoCommentsContext? = nil,
        authService: AuthService? = nil,
        photoIdsForSaving: [PhotoSaveId]? = nil,
        onAddToSaved: ((String, Int, Int, String?) async -> Bool)? = nil,
        getAccessToken: (() -> String)? = nil,
        isSavedAlbum: Bool = false,
        initialAccessToken: String = "",
        isOwnPhotos: Bool = false,
        onDeletePhoto: ((String, Int, Int) async -> Bool)? = nil,
        isProfileAlbum: Bool = false,
        onMakeProfilePhoto: ((String, Int, Int) async -> (Bool, String?))? = nil
    ) {
        self.urls = urls
        self.initialIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        self.onDismiss = onDismiss
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.isLiked = isLiked
        self.onLike = onLike
        self.onTapComments = onTapComments
        self.postCommentsContext = postCommentsContext
        self.photoCommentsContext = photoCommentsContext
        self.authService = authService
        self.photoIdsForSaving = photoIdsForSaving
        self.onAddToSaved = onAddToSaved
        self.getAccessToken = getAccessToken
        self.isSavedAlbum = isSavedAlbum
        self.initialAccessToken = initialAccessToken
        self.isOwnPhotos = isOwnPhotos
        self.onDeletePhoto = onDeletePhoto
        self.isProfileAlbum = isProfileAlbum
        self.onMakeProfilePhoto = onMakeProfilePhoto
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
        _capturedTokenForSave = State(initialValue: initialAccessToken)
    }

    private var displayLiked: Bool { likedOverride ?? isLiked }
    private var displayLikesCount: Int {
        guard let n = likesCount else { return 0 }
        if likedOverride == true, !isLiked { return n + 1 }
        if likedOverride == false, isLiked { return max(0, n - 1) }
        return n
    }

    private let swipeThreshold: CGFloat = 120

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
                TabView(selection: $currentIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        FullScreenImageView(imageURL: url, onDismiss: onDismiss) {
                            overlayVisible.toggle()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let dy = value.translation.height
                            let dx = value.translation.width
                            if dy > swipeThreshold && dy > abs(dx) {
                                onDismiss()
                            }
                        }
                )

                if overlayVisible {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)
                        bottomBar
                    }
                    .transition(.opacity)
                    .padding(.bottom, 60)
                }

                if showActionsOverlay {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { showActionsOverlay = false }
                    VStack(spacing: 0) {
                        if isOwnPhotos, isProfileAlbum, let makeProfile = onMakeProfilePhoto, let ids = photoIdsForSaving, currentIndex < ids.count {
                            Button {
                                let item = ids[currentIndex]
                                // Всегда брать актуальный токен в момент нажатия (в fullScreenCover старый capture может быть пустым).
                                let token = getAccessToken?() ?? authService?.accessToken ?? capturedTokenForSave
                                guard !token.isEmpty, !makeProfilePhotoInProgress else {
                                    showActionsOverlay = false
                                    if token.isEmpty {
                                        makeProfileErrorText = "Войдите в аккаунт снова"
                                        showMakeProfileErrorToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showMakeProfileErrorToast = false }
                                    }
                                    return
                                }
                                makeProfilePhotoInProgress = true
                                Task {
                                    let (ok, errorMessage) = await makeProfile(token, item.ownerId, item.photoId)
                                    await MainActor.run {
                                        makeProfilePhotoInProgress = false
                                        showActionsOverlay = false
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
                            } label: {
                                Label(makeProfilePhotoInProgress ? "Сохранение…" : "Сделать фото профиля", systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(makeProfilePhotoInProgress)
                            Divider()
                        }
                        if isOwnPhotos, let deletePhoto = onDeletePhoto, let ids = photoIdsForSaving, currentIndex < ids.count {
                            Button {
                                let item = ids[currentIndex]
                                let token = capturedTokenForSave.isEmpty ? (getAccessToken?() ?? authService?.accessToken ?? "") : capturedTokenForSave
                                guard !token.isEmpty, !deletePhotoInProgress else { showActionsOverlay = false; return }
                                deletePhotoInProgress = true
                                Task {
                                    let ok = await deletePhoto(token, item.ownerId, item.photoId)
                                    await MainActor.run {
                                        deletePhotoInProgress = false
                                        showActionsOverlay = false
                                        if ok { onDismiss() }
                                    }
                                }
                            } label: {
                                Label(deletePhotoInProgress ? "Удаление…" : "Удалить", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(deletePhotoInProgress)
                            Divider()
                        }
                        if !isOwnPhotos && !isSavedAlbum {
                            Button {
                                guard let ids = photoIdsForSaving, let save = onAddToSaved, currentIndex < ids.count, !addToSavedDone else {
                                    showActionsOverlay = false
                                    return
                                }
                                let item = ids[currentIndex]
                                let token = capturedTokenForSave.isEmpty ? (getAccessToken?() ?? authService?.accessToken ?? "") : capturedTokenForSave
                                addToSavedInProgress = true
                                addToSavedFailed = false
                                Task {
                                    let ok = await save(token, item.ownerId, item.photoId, item.accessKey)
                                    await MainActor.run {
                                        addToSavedInProgress = false
                                        showActionsOverlay = false
                                        if ok {
                                            addToSavedDone = true
                                            showSavedToast = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                                showSavedToast = false
                                            }
                                        } else {
                                            addToSavedFailed = true
                                            showFailedToast = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                                showFailedToast = false
                                            }
                                        }
                                    }
                                }
                            } label: {
                                let title = addToSavedDone ? "Добавлено в сохранённые" : (addToSavedFailed ? "Не удалось сохранить" : "Добавить в сохранённые")
                                Label(title, systemImage: addToSavedDone ? "checkmark.circle" : "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(addToSavedInProgress || addToSavedDone || photoIdsForSaving == nil || onAddToSaved == nil || currentIndex >= (photoIdsForSaving?.count ?? 0))
                            Divider()
                        }
                        Button("Закрыть") {
                            showActionsOverlay = false
                            onDismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.primary)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: 280)
                    .padding(.top, 56)
                    .zIndex(20)
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

                // Стрелки влево/вправо — почти прозрачные, перелистывание
                if urls.count > 1 {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentIndex = max(0, currentIndex - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(width: 56, height: 120)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(currentIndex > 0 ? 1 : 0.3)
                        .disabled(currentIndex <= 0)
                        .padding(.leading, 4)

                        Spacer(minLength: 0)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentIndex = min(urls.count - 1, currentIndex + 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(width: 56, height: 120)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(currentIndex < urls.count - 1 ? 1 : 0.3)
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
    }

    private var topBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            Spacer(minLength: 0)
            if !isSavedAlbum || (isOwnPhotos && (onDeletePhoto != nil || onMakeProfilePhoto != nil)) {
            Button {
                if capturedTokenForSave.isEmpty {
                    capturedTokenForSave = getAccessToken?() ?? authService?.accessToken ?? ""
                }
                showActionsOverlay = true
            } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 32) {
            if let action = onLike {
                Button {
                    likedOverride = !displayLiked
                    action()
                } label: {
                    Label(
                        "Нравится (\(displayLikesCount))",
                        systemImage: displayLiked ? "heart.fill" : "heart"
                    )
                }
                .font(.body)
                .foregroundStyle(displayLiked ? .red : .white)
                .buttonStyle(.plain)
            } else {
                Group {
                    if let n = likesCount {
                        Label("Нравится (\(n))", systemImage: "heart")
                    } else {
                        Label("Нравится", systemImage: "heart")
                    }
                }
                .font(.body)
                .foregroundStyle(.white)
            }

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
                    if let n = commentsCount {
                        Label("Комментарии (\(n))", systemImage: "bubble.right")
                    } else {
                        Label("Комментарии", systemImage: "bubble.right")
                    }
                }
                .font(.body)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            } else {
                Group {
                    if let n = commentsCount {
                        Label("Комментарии (\(n))", systemImage: "bubble.right")
                    } else {
                        Label("Комментарии", systemImage: "bubble.right")
                    }
                }
                .font(.body)
                .foregroundStyle(.white)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .padding(.bottom, 24)
        .background(Color.black.opacity(0.5))
    }
}
