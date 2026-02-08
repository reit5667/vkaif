import SwiftUI

/// Экран чата: история (getHistory), ввод и отправка (send), пагинация вверх.
struct ChatView: View {
    let peerId: Int
    /// Заголовок из списка диалогов (для бесед и быстрого отображения).
    let title: String?
    @ObservedObject var authService: AuthService

    @State private var messages: [VKMessage] = []
    @State private var profiles: [VKProfile] = []
    @State private var groups: [VKGroup] = []
    @State private var totalCount: Int = 0
    @State private var loadState: LoadState = .idle
    @State private var inputText: String = ""
    @State private var sending = false
    @State private var sendError: String?

    private let vkApi = VKApiService()
    private let pageSize = 30

    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    /// Заголовок: переданный title или из profiles/groups после загрузки.
    private var chatTitle: String {
        if let t = title, !t.isEmpty { return t }
        if peerId >= 200_000_0000 { return "Беседа" }
        if let p = profiles.first(where: { $0.id == peerId }) {
            let name = [p.firstName, p.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "ID\(p.id)" : name
        }
        if let g = groups.first(where: { -$0.id == peerId }) { return g.name ?? "ID\(peerId)" }
        return "Загрузка…"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = sendError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            messagesList
            inputBar
        }
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadHistory() }
        .refreshable { loadHistory(force: true) }
    }

    private var messagesList: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if messages.isEmpty {
                    ContentUnavailableView(
                        "Нет сообщений",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(messages, id: \.id) { msg in
                                messageRow(msg)
                                    .id(msg.id)
                            }
                            if messages.count < totalCount {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .onAppear { loadMoreHistory() }
                            }
                        }
                        .listStyle(.plain)
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            case .failed(let error):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageRow(_ msg: VKMessage) -> some View {
        let isOut = (msg.out ?? 0) == 1
        return HStack {
            if isOut { Spacer(minLength: 48) }
            VStack(alignment: isOut ? .trailing : .leading, spacing: 2) {
                Text(msg.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOut ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(shortTime(msg.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isOut { Spacer(minLength: 48) }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowSeparator(.hidden)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Сообщение", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
            Button {
                sendMessage()
            } label: {
                if sending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func loadHistory(force: Bool = false) {
        guard let token = authService.accessToken else {
            loadState = .failed(VKApiError.missingToken)
            return
        }
        if !force, case .loading = loadState { return }
        loadState = .loading
        Task {
            do {
                let res = try await vkApi.getHistory(token: token, peerId: peerId, count: pageSize, offset: 0)
                await MainActor.run {
                    messages = res.items.reversed()
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

    private func loadMoreHistory() {
        guard let token = authService.accessToken else { return }
        guard case .loaded = loadState, messages.count < totalCount else { return }
        Task {
            let offset = messages.count
            do {
                let res = try await vkApi.getHistory(token: token, peerId: peerId, count: pageSize, offset: offset)
                await MainActor.run {
                    let older = res.items.reversed()
                    messages = older + messages
                }
            } catch {
                // тихо не подгружать дальше при ошибке
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let token = authService.accessToken else { return }
        sending = true
        sendError = nil
        let randomId = Int.random(in: 1...Int.max)
        Task {
            do {
                _ = try await vkApi.sendMessage(token: token, peerId: peerId, message: text, randomId: randomId)
                await MainActor.run {
                    inputText = ""
                    sending = false
                    loadHistory(force: true)
                }
            } catch {
                await MainActor.run {
                    sending = false
                    sendError = error.localizedDescription
                }
            }
        }
    }
}
