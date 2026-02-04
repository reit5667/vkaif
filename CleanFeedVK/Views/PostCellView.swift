import SwiftUI

// MARK: - Ячейка поста ленты

/// Заголовок: аватар, имя, относительная дата. Тело: текст с «Показать ещё». Медиа: сетка фото (1–10).
struct PostCellView: View {

    let post: VKPost
    let authorName: String
    let authorAvatarURL: String?
    let relativeDate: String
    /// Для навигации из ленты: тап по автору → группа/профиль. nil в превью или на стене группы.
    var authService: AuthService? = nil
    var feedDestination: FeedDestination? = nil
    /// Тап по счётчику комментариев → открыть экран комментариев. nil = не открывать.
    var onTapComments: (() -> Void)? = nil
    /// Переопределение счётчика лайков (после likes.add). nil = брать из post.
    var likesCountOverride: Int? = nil
    /// Переопределение «лайкнуто» (после likes.add). nil = из post.likes?.userLikes.
    var isLikedOverride: Bool? = nil
    /// Тап по лайку → поставить лайк. nil = только отображение.
    var onLike: (() -> Void)? = nil
    /// true = запрос лайка в процессе, кнопку не нажимать.
    var likeInProgress: Bool = false
    /// Тап по видео → загрузка player URL и открытие плеера. Передаётся пост для панели лайков/комментариев.
    var onTapVideo: ((VKVideo, Int, VKPost) async -> Void)? = nil

    @State private var isTextExpanded = false
    @State private var fullScreenPhotoIndex: Int? = nil
    private let textLineLimitCollapsed = 3

    /// URL фото для превью: приоритет feedPreviewURL (меньше трафика), fallback на displayURL для надёжности.
    private var photoThumbnailURLs: [String] {
        guard let attachments = post.attachments else { return [] }
        return attachments.compactMap { p in p.photo?.feedPreviewURL ?? p.photo?.displayURL }
    }

    /// URL фото для полноэкранного просмотра (крупные размеры).
    private var photoDisplayURLs: [String] {
        guard let attachments = post.attachments else { return [] }
        return attachments.compactMap { $0.photo?.displayURL }
    }

    private var photoThumbnailURLsAsURLs: [URL] { photoThumbnailURLs.compactMap { URL(string: $0) } }
    private var photoDisplayURLsAsURLs: [URL] { photoDisplayURLs.compactMap { URL(string: $0) } }

    /// Видео из вложений поста с ownerId для плеера/video.get.
    private var videoAttachments: [(video: VKVideo, ownerId: Int)] {
        let owner = post.ownerId ?? post.fromId ?? 0
        return (post.attachments ?? [])
            .compactMap { att -> (VKVideo, Int)? in
                guard let v = att.video else { return nil }
                return (v, owner)
            }
    }

    private var linkAttachments: [VKLink] {
        (post.attachments ?? []).compactMap { $0.link }
    }

    private var pollAttachments: [VKPoll] {
        (post.attachments ?? []).compactMap { $0.poll }
    }

    /// Есть вложения, которые не фото/видео/ссылка/опрос — показываем плейсхолдер (doc и т.д.).
    private var hasOtherMedia: Bool {
        guard let attachments = post.attachments else { return false }
        return attachments.contains { att in
            att.photo == nil && att.video == nil && att.link == nil && att.poll == nil && att.doc != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !post.text.isEmpty {
                bodyText
            }
            if !photoThumbnailURLs.isEmpty {
                photoGridView
            }
            if !videoAttachments.isEmpty {
                videoRow
            }
            if !linkAttachments.isEmpty {
                linkRow
            }
            if !pollAttachments.isEmpty {
                pollRow
            }
            if hasOtherMedia {
                mediaPlaceholder
            }
            if displayLikesCount > 0 || onLike != nil || post.commentsCount > 0 || onTapComments != nil {
                likesCommentsRow
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .fullScreenCover(isPresented: Binding(
            get: { fullScreenPhotoIndex != nil },
            set: { if !$0 { fullScreenPhotoIndex = nil } }
        )) {
            if let idx = fullScreenPhotoIndex, !photoDisplayURLsAsURLs.isEmpty {
                let ownerId = post.ownerId ?? post.fromId ?? 0
                FullScreenPhotoGalleryView(
                    urls: photoDisplayURLsAsURLs,
                    initialIndex: min(idx, photoDisplayURLsAsURLs.count - 1),
                    onDismiss: { fullScreenPhotoIndex = nil },
                    likesCount: displayLikesCount,
                    commentsCount: post.commentsCount,
                    isLiked: displayIsLiked,
                    onLike: likeInProgress ? nil : onLike,
                    onTapComments: onTapComments,
                    postCommentsContext: (onTapComments != nil && authService != nil)
                        ? PostCommentsContext(ownerId: ownerId, postId: post.id, totalCount: post.commentsCount)
                        : nil,
                    authService: authService
                )
            }
        }
    }

    // MARK: - Header (тап → группа или профиль, если передан feedDestination)

    private var headerContent: some View {
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
    private var header: some View {
        if let dest = feedDestination {
            NavigationLink(value: dest) { headerContent }
        } else {
            headerContent
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


    /// Сетка фото: 1 — во всю ширину, 2 — два столбца, 3+ — до 3 столбцов.
    private var photoGridView: some View {
        let count = photoThumbnailURLs.count
        let columnsCount = count == 1 ? 1 : (count == 2 ? 2 : min(3, count))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnsCount)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(photoThumbnailURLs.enumerated()), id: \.offset) { index, urlString in
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

    /// Строка видео: превью или плейсхолдер, тап → onTapVideo (плеер). Сетка по центру.
    @ViewBuilder
    private var videoRow: some View {
        let count = videoAttachments.count
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let grid = LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(videoAttachments.enumerated()), id: \.offset) { _, pair in
                videoCard(video: pair.video, ownerId: pair.ownerId)
            }
        }
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            grid
                .frame(maxWidth: count <= 2 ? (count == 1 ? 180 : 280) : nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func videoCard(video: VKVideo, ownerId: Int) -> some View {
        let previewURL = video.previewImageURL
        return Button {
            Task { await onTapVideo?(video, ownerId, post) }
        } label: {
            ZStack(alignment: .center) {
                if let urlString = previewURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            videoPlaceholderContent(duration: video.duration)
                        @unknown default:
                            videoPlaceholderContent(duration: video.duration)
                        }
                    }
                } else {
                    videoPlaceholderContent(duration: video.duration)
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(onTapVideo == nil)
    }

    private func videoPlaceholderContent(duration: Int?) -> some View {
        VStack(spacing: 4) {
            if let sec = duration {
                Text(formatDuration(sec))
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray4))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return "0:\(String(format: "%02d", s))"
    }

    /// Ссылки: заголовок/URL, тап → Safari.
    private var linkRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(linkAttachments.enumerated()), id: \.offset) { _, link in
                if let url = URL(string: link.url) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                if let t = link.title, !t.isEmpty {
                                    Text(t)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }
                                Text(link.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Опросы: вопрос и варианты ответов (только отображение).
    private var pollRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pollAttachments.enumerated()), id: \.offset) { _, poll in
                VStack(alignment: .leading, spacing: 6) {
                    if let q = poll.question, !q.isEmpty {
                        Text(q)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    if let answers = poll.answers, !answers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(answers, id: \.id) { a in
                                HStack(spacing: 8) {
                                    Text(a.text ?? "")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    if let v = a.votes {
                                        Text("\(v)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            }
                        }
                    }
                    if let votes = poll.votes {
                        Text("Всего голосов: \(votes)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    private var mediaPlaceholder: some View {
        HStack {
            Image(systemName: "doc")
                .foregroundColor(.secondary)
            Text("Документ")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Лайки / комментарии (счётчики)

    private var displayLikesCount: Int {
        likesCountOverride ?? post.likesCount
    }

    private var displayIsLiked: Bool {
        isLikedOverride ?? (post.likes?.userLikes == 1)
    }

    private var likesCommentsRow: some View {
        HStack(spacing: 16) {
            if displayLikesCount > 0 || onLike != nil {
                if let action = onLike {
                    Button(action: action) {
                        Label(
                            "\(displayLikesCount)",
                            systemImage: displayIsLiked ? "heart.fill" : "heart"
                        )
                        .font(.caption)
                        .foregroundColor(displayIsLiked ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(likeInProgress)
                } else {
                    Label("\(displayLikesCount)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if onTapComments != nil {
                Button(action: { onTapComments?() }) {
                    Label("\(post.commentsCount)", systemImage: "bubble.right.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else if post.commentsCount > 0 {
                Label("\(post.commentsCount)", systemImage: "bubble.right.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
    init(id: Int, fromId: Int?, ownerId: Int?, date: Date, text: String, markedAsAds: Int?, postType: String?, sourceType: String?, attachments: [VKAttachment]?, copyHistory: [VKPost]?, likes: VKPostLikes? = nil, comments: VKPostComments? = nil) {
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
        self.likes = likes
        self.comments = comments
    }
}
