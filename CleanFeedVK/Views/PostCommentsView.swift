import SwiftUI

/// Контекст открытия комментариев к посту (для sheet).
struct PostCommentsContext: Identifiable {
    let ownerId: Int
    let postId: Int
    let totalCount: Int
    var id: String { "\(ownerId)_\(postId)" }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .onAppear(perform: performInitialLoadIfNeeded)
    }

    /// Вызов при появлении экрана: загрузить первую порцию, если ещё не начинали.
    private func performInitialLoadIfNeeded() {
        if case .idle = loadState { loadFirstPage() }
    }

    private var commentsList: some View {
        List {
            ForEach(items, id: \.id) { comment in
                commentRow(comment)
            }
            if !items.isEmpty && items.count < totalFromApi {
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
                Text(commentAuthorName(comment))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(relativeDateString(from: comment.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let likes = comment.likes, likes.count > 0 {
                Label("\(likes.count)", systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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
                    items.append(contentsOf: response.items)
                    mergeProfiles(response.profiles ?? [])
                    mergeGroups(response.groups ?? [])
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
