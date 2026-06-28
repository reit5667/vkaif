import SwiftUI

/// Таб «Сообщения»: список диалогов (getConversations), переход в чат по peer_id.
struct MessagesTabView: View {
    @ObservedObject var authService: AuthService

    @StateObject private var chatCache = ChatViewModelCache()

    @State private var items: [VKConversationItem] = []
    @State private var profiles: [VKProfile] = []
    @State private var groups: [VKGroup] = []
    @State private var totalCount: Int = 0
    @State private var isLoadingMore: Bool = false
    @State private var loadState: LoadState = .idle
    @State private var searchText: String = ""

    private var filteredItems: [VKConversationItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter { displayTitle(for: $0).lowercased().contains(q) }
    }

    private let vkApi = VKApiService()
    private let pageSize = 50

    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка диалогов…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                listContent
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadConversations() }
        .navigationDestination(for: ChatDestination.self) { dest in
            let vm = chatCache.viewModel(for: dest.peerId)
            ChatView(viewModel: vm, title: dest.title, authService: authService)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(VKTheme.Colors.textSecondary)
                TextField("Поиск", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(VKTheme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            Divider()

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Нет диалогов" : "Ничего не найдено",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(searchText.isEmpty ? "Диалоги появятся здесь." : "Попробуйте другой запрос")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems, id: \.conversation.peer.id) { item in
                            NavigationLink(value: ChatDestination(peerId: item.conversation.peer.id, title: displayTitle(for: item))) {
                                dialogRow(item)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 72)
                        }
                        if items.count < totalCount {
                            ProgressView("Подгрузка диалогов…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .onAppear { loadMoreConversations() }
                        }
                    }
                }
                .background(Color.white)
                .refreshable { loadConversations(force: true) }
            }
        }
    }

    private func dialogRow(_ item: VKConversationItem) -> some View {
        let unread = item.conversation.unreadCount ?? 0
        let isUnread = unread > 0
        let isOutgoing = item.lastMessage.out == 1
        let preview = item.lastMessage.text.isEmpty ? "Вложение" : item.lastMessage.text

        return HStack(spacing: 12) {
            avatarView(url: avatarURL(for: item))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: item))
                    .font(.system(size: 15, weight: isUnread ? .bold : .semibold))
                    .foregroundColor(VKTheme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    if isOutgoing {
                        Text("Вы: ")
                            .font(VKTheme.TextStyle.dialogPreview)
                            .foregroundColor(VKTheme.Colors.textSecondary)
                    }
                    Text(preview)
                        .font(VKTheme.TextStyle.dialogPreview)
                        .foregroundColor(VKTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(shortDate(item.lastMessage.date))
                    .font(.system(size: 13))
                    .foregroundColor(isUnread ? VKTheme.Colors.badge : VKTheme.Colors.textSecondary)
                if isUnread {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VKTheme.Colors.badge)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    private func displayTitle(for item: VKConversationItem) -> String {
        let peer = item.conversation.peer
        if peer.id >= 200_000_0000 {
            return item.conversation.chatSettings?.title?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? (item.conversation.chatSettings?.title ?? "Беседа")
                : "Беседа"
        }
        if let p = profiles.first(where: { $0.id == peer.id }) {
            let name = [p.firstName, p.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "ID\(p.id)" : name
        }
        return "ID\(peer.id)"
    }

    private func avatarURL(for item: VKConversationItem) -> String? {
        let peer = item.conversation.peer
        if peer.id >= 200_000_0000 {
            return nil
        }
        return profiles.first(where: { $0.id == peer.id })?.photo50
            ?? groups.first(where: { -$0.id == peer.id })?.photo50
    }

    private func avatarView(url: String?) -> some View {
        Group {
            if let urlString = url, let u = URL(string: urlString) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure, .empty: Image(systemName: "person.circle.fill").resizable().foregroundStyle(.secondary)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: VKTheme.AvatarSize.dialog, height: VKTheme.AvatarSize.dialog)
        .clipShape(Circle())
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Вчера"
        }
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        return f.string(from: date)
    }

    private func loadConversations(force: Bool = false) {
        guard let token = authService.accessToken else {
            loadState = .failed(VKApiError.missingToken)
            return
        }
        if !force, case .loading = loadState { return }
        if !force, case .loaded = loadState { return }
        loadState = .loading
        if force {
            items = []
            totalCount = 0
        }
        Task {
            do {
                let res = try await vkApi.getConversations(token: token, count: pageSize, offset: 0)
                await MainActor.run {
                    items = res.items
                    totalCount = res.count
                    profiles = res.profiles ?? []
                    groups = res.groups ?? []
                    loadState = .loaded
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }

    private func loadMoreConversations() {
        guard let token = authService.accessToken else { return }
        guard case .loaded = loadState, items.count < totalCount, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = items.count
        Task {
            do {
                let res = try await vkApi.getConversations(token: token, count: pageSize, offset: offset)
                await MainActor.run {
                    items.append(contentsOf: res.items)
                    mergeProfiles(res.profiles ?? [])
                    mergeGroups(res.groups ?? [])
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run { isLoadingMore = false }
            }
        }
    }

    private func mergeProfiles(_ new: [VKProfile]) {
        var ids = Set(profiles.map(\.id))
        for p in new where ids.insert(p.id).inserted {
            profiles.append(p)
        }
    }

    private func mergeGroups(_ new: [VKGroup]) {
        var ids = Set(groups.map(\.id))
        for g in new where ids.insert(g.id).inserted {
            groups.append(g)
        }
    }
}

/// Навигация в чат: peer_id и уже известный заголовок (чтобы не ждать getHistory).
struct ChatDestination: Hashable {
    let peerId: Int
    let title: String
}
