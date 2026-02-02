import SwiftUI

// MARK: - Ячейка поста ленты

/// Заголовок: аватар, имя, относительная дата. Тело: текст с «Показать ещё». Медиа: сетка фото (1–10).
struct PostCellView: View {

    let post: VKPost
    let authorName: String
    let authorAvatarURL: String?
    let relativeDate: String

    @State private var isTextExpanded = false
    @State private var fullScreenPhotoIndex: Int? = nil
    private let textLineLimitCollapsed = 3

    /// URL только фото из вложений (для сетки).
    private var photoURLs: [String] {
        guard let attachments = post.attachments else { return [] }
        return attachments.compactMap { $0.photo?.displayURL }
    }

    private var photoURLsAsURLs: [URL] { photoURLs.compactMap { URL(string: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !post.text.isEmpty {
                bodyText
            }
            if !photoURLs.isEmpty {
                photoGridView
            } else if hasNonPhotoMedia {
                mediaPlaceholder
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .fullScreenCover(isPresented: Binding(
            get: { fullScreenPhotoIndex != nil },
            set: { if !$0 { fullScreenPhotoIndex = nil } }
        )) {
            if let idx = fullScreenPhotoIndex, !photoURLsAsURLs.isEmpty {
                FullScreenPhotoGalleryView(
                    urls: photoURLsAsURLs,
                    initialIndex: min(idx, photoURLsAsURLs.count - 1),
                    onDismiss: { fullScreenPhotoIndex = nil }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(relativeDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = authorAvatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Body text

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.text)
                .font(.body)
                .lineLimit(isTextExpanded ? nil : textLineLimitCollapsed)
                .frame(maxWidth: .infinity, alignment: .leading)

            if post.text.count > 100 {
                Button(isTextExpanded ? "Свернуть" : "Показать ещё") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTextExpanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - Media

    private var hasNonPhotoMedia: Bool {
        guard let attachments = post.attachments else { return false }
        return attachments.contains { $0.video != nil || $0.link != nil }
    }

    /// Сетка фото: 1 — во всю ширину, 2 — два столбца, 3+ — до 3 столбцов.
    private var photoGridView: some View {
        let count = photoURLs.count
        let columnsCount = count == 1 ? 1 : (count == 2 ? 2 : min(3, count))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnsCount)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, urlString in
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            ProgressView()
                        }
                    }
                    .frame(minHeight: count == 1 ? 200 : 120)
                    .frame(maxWidth: count == 1 ? .infinity : nil)
                    .clipped()
                    .cornerRadius(8)
                    .onTapGesture { fullScreenPhotoIndex = index }
                }
            }
        }
    }

    private var mediaPlaceholder: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundColor(.secondary)
            Text("Видео / ссылка")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Helpers

/// Относительная дата: "2 ч назад", "вчера", "15 янв".
func relativeDateString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

/// Имя автора поста: из profiles (положительный fromId) или groups (отрицательный ownerId).
func authorName(for post: VKPost, profiles: [VKProfile], groups: [VKGroup]) -> String {
    let fromId = post.fromId ?? post.ownerId ?? 0
    if fromId > 0 {
        if let p = profiles.first(where: { $0.id == fromId }) {
            return [p.firstName, p.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    } else {
        let groupId = abs(fromId)
        if let g = groups.first(where: { $0.id == groupId }) {
            return g.name ?? "Группа"
        }
    }
    return "Автор"
}

/// URL аватара 50x50 для автора поста.
func authorAvatarURL(for post: VKPost, profiles: [VKProfile], groups: [VKGroup]) -> String? {
    let fromId = post.fromId ?? post.ownerId ?? 0
    if fromId > 0 {
        return profiles.first(where: { $0.id == fromId })?.photo50
    } else {
        let groupId = abs(fromId)
        return groups.first(where: { $0.id == groupId })?.photo50
    }
}

#Preview {
    let post = VKPost(
        id: 1,
        fromId: 1,
        ownerId: 1,
        date: Date(),
        text: "Пример текста поста. Он может быть длинным и тогда появится кнопка «Показать ещё», чтобы развернуть весь текст и прочитать его полностью.",
        markedAsAds: nil,
        postType: nil,
        sourceType: nil,
        attachments: nil,
        copyHistory: nil
    )
    return PostCellView(
        post: post,
        authorName: "Иван Иванов",
        authorAvatarURL: nil,
        relativeDate: "2 ч назад"
    )
    .padding()
}

// Инициализатор для превью (VKPost из Decoder только)
extension VKPost {
    init(id: Int, fromId: Int?, ownerId: Int?, date: Date, text: String, markedAsAds: Int?, postType: String?, sourceType: String?, attachments: [VKAttachment]?, copyHistory: [VKPost]?) {
        self.id = id
        self.fromId = fromId
        self.ownerId = ownerId
        self.date = date
        self.text = text
        self.markedAsAds = markedAsAds
        self.postType = postType
        self.sourceType = sourceType
        self.attachments = attachments
        self.copyHistory = copyHistory
    }
}
