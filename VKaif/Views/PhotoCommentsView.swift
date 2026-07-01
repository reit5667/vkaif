import SwiftUI

/// Контекст открытия комментариев к фото (для sheet из альбома).
struct PhotoCommentsContext: Identifiable {
    let ownerId: Int
    let photoId: Int
    var id: String { "photo_\(ownerId)_\(photoId)" }
}

/// Комментарии к фото: photos.getComments, список + «Назад».
struct PhotoCommentsView: View {
    let context: PhotoCommentsContext
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var items: [VKComment] = []
    @State private var profiles: [VKProfile] = []
    @State private var groups: [VKGroup] = []
    @State private var totalFromApi: Int = 0
    @State private var loadState: LoadState = .idle
    @State private var loadMoreLoading = false
    @State private var authorDestination: AuthorDest? = nil
    @State private var noMoreTopLevel = false

    private let vkApi = VKApiService()
    private let pageSize = 20

    private enum LoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    private enum AuthorDest: Hashable, Identifiable {
        case user(id: Int)
        case group(id: Int)
        var id: String {
            switch self {
            case .user(let i): return "user-\(i)"
            case .group(let i): return "group-\(i)"
            }
        }
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
            .navigationTitle("Комментарии к фото")
            .navigationBarTitleDisplayMode(.inline)
            .vkBlueNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Назад", systemImage: "chevron.left")
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
        .onAppear { if case .idle = loadState { loadFirstPage() } }
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
            if !items.isEmpty && items.count < totalFromApi && !noMoreTopLevel {
                Section {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            if loadMoreLoading { ProgressView().scaleEffect(0.9) }
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
                Text(relativeDate(from: comment.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func authorLink(_ comment: VKComment) -> some View {
        if comment.fromId > 0 {
            Button {
                authorDestination = .user(id: comment.fromId)
            } label: {
                Text(authorName(comment))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                authorDestination = .group(id: abs(comment.fromId))
            } label: {
                Text(authorName(comment))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func authorName(_ comment: VKComment) -> String {
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

    private func relativeDate(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
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
            let response = try await vkApi.getPhotoComments(
                token: token,
                ownerId: context.ownerId,
                photoId: context.photoId,
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
        let ids = Set(profiles.map(\.id))
        profiles.append(contentsOf: new.filter { !ids.contains($0.id) })
    }

    private func mergeGroups(_ new: [VKGroup]) {
        let ids = Set(groups.map(\.id))
        groups.append(contentsOf: new.filter { !ids.contains($0.id) })
    }
}
