import SwiftUI

/// Контекст открытия комментариев к посту (для sheet).
struct PostCommentsContext: Identifiable {
    let ownerId: Int
    let postId: Int
    let totalCount: Int
    var id: String { "\(ownerId)_\(postId)" }
}

/// Навигация из экрана комментариев: только по явному тапу на имя автора.
private enum CommentAuthorDestination: Hashable, Identifiable {
    case user(id: Int)
    case group(id: Int)
    var id: String {
        switch self {
        case .user(let i): return "user-\(i)"
        case .group(let i): return "group-\(i)"
        }
    }
}

/// Цель добавления комментария: корневой или ответ на комментарий (для sheet).
private enum AddCommentTarget: Identifiable {
    case root
    case reply(VKComment)
    var id: String {
        switch self {
        case .root: return "root"
        case .reply(let c): return "reply-\(c.id)"
        }
    }
}

/// Экран комментариев к посту: список с пагинацией по 5, «Подгрузить ещё».
struct PostCommentsView: View {
    let context: PostCommentsContext
    @ObservedObject var authService: AuthService

    @State private var items: [VKComment] = []
    @State private var profiles: [VKProfile] = []
    @State private var groups: [VKGroup] = []
    @State private var totalFromApi: Int = 0
    @State private var loadState: CommentsLoadState = .idle
    @State private var loadMoreLoading = false
    @State private var commentLikeOverrides: [Int: Int] = [:]      // comment id -> новый count
    @State private var commentLikedOverrides: [Int: Bool] = [:]    // comment id -> лайкнуто
    @State private var likeInProgress: Set<Int> = []
    @State private var addCommentTarget: AddCommentTarget? = nil
    @State private var replyText: String = ""
    @State private var replySending = false
    @State private var replyError: String? = nil
    /// Навигация на профиль/группу только по явному тапу на имя; задаётся кнопкой, не NavigationLink(value:).
    @State private var authorDestination: CommentAuthorDestination? = nil
    /// После подгрузки с offset получили 0 записей — больше топ-уровня нет, кнопку «Подгрузить ещё» скрыть.
    @State private var noMoreTopLevel = false
    @Environment(\.dismiss) private var dismiss

    private let vkApi = VKApiService()
    private let pageSize = 5

    private enum CommentsLoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .idle, .loading:
                    ProgressView("Загрузка комментариев…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded:
                    commentsList
                case .failed(let error):
                    VStack(spacing: 12) {
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Повторить") { loadFirstPage() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Комментарии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Назад", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if case .loaded = loadState {
                        Button("Добавить комментарий") {
                            addCommentTarget = .root
                            replyText = ""
                            replyError = nil
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .navigationDestination(item: $authorDestination) { dest in
                switch dest {
                case .user(let id):
                    ProfileViewWrapper(authService: authService, userId: id)
                case .group(let id):
                    GroupWallView(authService: authService, groupId: id)
                }
            }
        }
        .onAppear(perform: performInitialLoadIfNeeded)
        .sheet(item: $addCommentTarget) { target in
            addCommentSheet(target: target)
        }
    }

    /// Вызов при появлении экрана: загрузить первую порцию, если ещё не начинали.
    private func performInitialLoadIfNeeded() {
        if case .idle = loadState { loadFirstPage() }
    }

    private var commentsList: some View {
        List {
            ForEach(items, id: \.id) { comment in
                commentRow(comment)
                if let threadItems = comment.thread?.items, !threadItems.isEmpty {
                    ForEach(threadItems, id: \.id) { reply in
                        commentRow(reply)
                            .padding(.leading, 12)
                    }
                }
            }
            if !items.isEmpty && items.count < totalFromApi && totalFromApi > 5 && !noMoreTopLevel {
                Section {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            if loadMoreLoading {
                                ProgressView()
                                    .scaleEffect(0.9)
                            }
                            Text(loadMoreLoading ? "Загрузка…" : "Подгрузить ещё")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(loadMoreLoading)
                }
            }
        }
    }

    private func commentRow(_ comment: VKComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                authorLink(comment)
                Text(relativeDateString(from: comment.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                likeButton(comment)
                Button("Ответить") {
                    addCommentTarget = .reply(comment)
                    replyText = ""
                    replyError = nil
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    /// Только тап по имени открывает профиль/группу; не реагируем на тап по строке/«Ответить».
    @ViewBuilder
    private func authorLink(_ comment: VKComment) -> some View {
        if comment.fromId > 0 {
            Button {
                authorDestination = .user(id: comment.fromId)
            } label: {
                Text(commentAuthorName(comment))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                authorDestination = .group(id: abs(comment.fromId))
            } label: {
                Text(commentAuthorName(comment))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func commentLikesCount(_ comment: VKComment) -> Int {
        commentLikeOverrides[comment.id] ?? comment.likes?.count ?? 0
    }

    private func commentIsLiked(_ comment: VKComment) -> Bool {
        commentLikedOverrides[comment.id] ?? (comment.likes?.userLikes == 1)
    }

    private func likeButton(_ comment: VKComment) -> some View {
        let count = commentLikesCount(comment)
        let liked = commentIsLiked(comment)
        let loading = likeInProgress.contains(comment.id)
        return Button {
            likeComment(comment)
        } label: {
            Label(
                count > 0 ? "\(count)" : "0",
                systemImage: liked ? "heart.fill" : "heart"
            )
            .font(.caption)
            .foregroundColor(liked ? .red : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    /// Toggle лайка комментария: если лайкнут — likes.delete, иначе likes.add.
    private func likeComment(_ comment: VKComment) {
        guard let token = authService.accessToken else { return }
        let cid = comment.id
        if likeInProgress.contains(cid) { return }
        let liked = commentLikedOverrides[cid] ?? (comment.likes?.userLikes == 1)
        likeInProgress.insert(cid)
        Task {
            do {
                let newCount: Int
                if liked {
                    newCount = try await vkApi.likesDelete(
                        token: token,
                        type: "comment",
                        ownerId: context.ownerId,
                        itemId: cid
                    )
                    await MainActor.run {
                        commentLikeOverrides[cid] = newCount
                        commentLikedOverrides[cid] = false
                        likeInProgress.remove(cid)
                    }
                } else {
                    newCount = try await vkApi.likesAdd(
                        token: token,
                        type: "comment",
                        ownerId: context.ownerId,
                        itemId: cid
                    )
                    await MainActor.run {
                        commentLikeOverrides[cid] = newCount
                        commentLikedOverrides[cid] = true
                        likeInProgress.remove(cid)
                    }
                }
            } catch {
                await MainActor.run { likeInProgress.remove(cid) }
            }
        }
    }

    /// Sheet: добавление корневого комментария или ответа на комментарий.
    private func addCommentSheet(target: AddCommentTarget) -> some View {
        let isReply: Bool
        let title: String
        switch target {
        case .root:
            isReply = false
            title = "Добавить комментарий"
        case .reply:
            isReply = true
            title = "Ответить"
        }
        return NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(isReply ? "Ответ на комментарий" : "Текст комментария")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(isReply ? "Текст ответа" : "Текст комментария", text: $replyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                if let err = replyError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        addCommentTarget = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отправить") {
                        sendComment(message: replyText, replyTo: target)
                    }
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replySending)
                }
            }
        }
        .onDisappear {
            replyText = ""
            replyError = nil
        }
    }

    private func sendComment(message: String, replyTo target: AddCommentTarget) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let token = authService.accessToken else { return }
        let replyToCommentId: Int?
        switch target {
        case .root: replyToCommentId = nil
        case .reply(let c): replyToCommentId = c.id
        }
        replySending = true
        replyError = nil
        Task {
            do {
                _ = try await vkApi.wallCreateComment(
                    token: token,
                    ownerId: context.ownerId,
                    postId: context.postId,
                    message: text,
                    replyTo: replyToCommentId
                )
                await MainActor.run {
                    replySending = false
                    addCommentTarget = nil
                    loadFirstPage()
                }
            } catch {
                await MainActor.run {
                    replySending = false
                    replyError = error.localizedDescription
                }
            }
        }
    }

    private func commentAuthorName(_ comment: VKComment) -> String {
        if comment.fromId > 0 {
            if let p = profiles.first(where: { $0.id == comment.fromId }) {
                return [p.firstName, p.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            }
        } else {
            let gid = abs(comment.fromId)
            if let g = groups.first(where: { $0.id == gid }) {
                return g.name ?? "Группа"
            }
        }
        return "ID\(comment.fromId)"
    }

    private func loadFirstPage() {
        noMoreTopLevel = false
        loadState = .loading
        Task {
            await fetch(offset: 0, append: false)
        }
    }

    private func loadMore() {
        guard !loadMoreLoading else { return }
        loadMoreLoading = true
        Task {
            await fetch(offset: items.count, append: true)
            loadMoreLoading = false
        }
    }

    private func fetch(offset: Int, append: Bool) async {
        guard let token = authService.accessToken else {
            await MainActor.run { loadState = .failed(VKApiError.missingToken) }
            return
        }
        do {
            let response = try await vkApi.getWallComments(
                token: token,
                ownerId: context.ownerId,
                postId: context.postId,
                offset: offset,
                count: pageSize,
                sort: "asc"
            )
            await MainActor.run {
                if append {
                    if response.items.isEmpty {
                        noMoreTopLevel = true
                    } else {
                        items.append(contentsOf: response.items)
                        mergeProfiles(response.profiles ?? [])
                        mergeGroups(response.groups ?? [])
                    }
                } else {
                    items = response.items
                    profiles = response.profiles ?? []
                    groups = response.groups ?? []
                }
                totalFromApi = response.count
                loadState = .loaded
            }
        } catch {
            await MainActor.run {
                if !append { loadState = .failed(error) }
            }
        }
    }

    private func mergeProfiles(_ new: [VKProfile]) {
        let existingIds = Set(profiles.map(\.id))
        profiles.append(contentsOf: new.filter { !existingIds.contains($0.id) })
    }

    private func mergeGroups(_ new: [VKGroup]) {
        let existingIds = Set(groups.map(\.id))
        groups.append(contentsOf: new.filter { !existingIds.contains($0.id) })
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
