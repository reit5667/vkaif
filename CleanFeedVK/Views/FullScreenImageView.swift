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

// MARK: - Галерея с пролистыванием (пост / альбом)

/// Несколько фото на весь экран: PageView, панель по тапу (лайк, комментарии, 3 точки), закрытие — кнопка или свайп вниз.
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

    @State private var currentIndex: Int
    @State private var overlayVisible = false
    /// Локальное переопределение после тапа «Нравится» до закрытия галереи.
    @State private var likedOverride: Bool? = nil

    init(
        urls: [URL],
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        likesCount: Int? = nil,
        commentsCount: Int? = nil,
        isLiked: Bool = false,
        onLike: (() -> Void)? = nil,
        onTapComments: (() -> Void)? = nil
    ) {
        self.urls = urls
        self.initialIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        self.onDismiss = onDismiss
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.isLiked = isLiked
        self.onLike = onLike
        self.onTapComments = onTapComments
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
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
        .onAppear { currentIndex = initialIndex }
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
            Menu {
                Button {
                    // TODO: добавить в альбом (photos.copy или аналог)
                } label: {
                    Label("Добавить в альбом", systemImage: "square.and.arrow.down")
                }
                .disabled(true)
                Divider()
                Button("Закрыть") { onDismiss() }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
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

            if let action = onTapComments {
                Button(action: action) {
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
