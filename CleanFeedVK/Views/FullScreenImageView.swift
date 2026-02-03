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

    @State private var currentIndex: Int
    @State private var overlayVisible = false

    init(urls: [URL], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.urls = urls
        self.initialIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
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
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .automatic))
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
                }
            }
        }
        .onAppear { currentIndex = initialIndex }
    }

    private var topBar: some View {
        HStack {
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
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.down.circle.fill")
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
            Button {
                // TODO: лайк фото (likes.add для photo)
            } label: {
                Label("Нравится", systemImage: "heart")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                // TODO: комментарии к фото
            } label: {
                Label("Комментарии", systemImage: "bubble.right")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.5))
    }
}
