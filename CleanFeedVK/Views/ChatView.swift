import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

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
    @State private var isLoadingMore = false
    @State private var lastMessageId: Int?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

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
                            if messages.count < totalCount {
                                ProgressView("Загрузка старых сообщений…")
                                    .frame(maxWidth: .infinity)
                                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                                    .onAppear { loadMoreHistory() }
                            }
                            ForEach(messages, id: \.id) { msg in
                                messageRow(msg)
                                    .id(msg.id)
                            }
                        }
                        .listStyle(.plain)
                        .onChange(of: messages.count) { oldCount, newCount in
                            let newLastId = messages.last?.id
                            if newLastId != lastMessageId {
                                lastMessageId = newLastId
                                scrollToBottom(proxy: proxy)
                            }
                        }
                        .onAppear {
                            lastMessageId = messages.last?.id
                            scrollToBottom(proxy: proxy)
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

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: "photo.circle.fill")
                    .font(.title2)
            }
            .disabled(sending)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task { await sendPhoto(from: item) }
            }
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
                    lastMessageId = messages.last?.id
                }
            } catch {
                await MainActor.run { loadState = .failed(error) }
            }
        }
    }

    private func loadMoreHistory() {
        guard let token = authService.accessToken else { return }
        guard case .loaded = loadState, messages.count < totalCount, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = messages.count
        Task {
            do {
                let res = try await vkApi.getHistory(token: token, peerId: peerId, count: pageSize, offset: offset)
                await MainActor.run {
                    let older = res.items.reversed()
                    messages = older + messages
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run { isLoadingMore = false }
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
                let messageId = try await vkApi.sendMessage(token: token, peerId: peerId, message: text, randomId: randomId)
                let fromId = messages.first(where: { ($0.out ?? 0) == 1 })?.fromId ?? 0
                let newMsg = VKMessage(
                    id: messageId,
                    fromId: fromId,
                    peerId: peerId,
                    date: Date(),
                    text: text,
                    out: 1,
                    readState: nil
                )
                await MainActor.run {
                    inputText = ""
                    sending = false
                    messages.append(newMsg)
                    totalCount += 1
                }
            } catch {
                await MainActor.run {
                    sending = false
                    sendError = error.localizedDescription
                }
            }
        }
    }

    private func sendPhoto(from item: PhotosPickerItem) async {
        guard let token = authService.accessToken else {
            await MainActor.run { sendError = "Нет доступа" }
            return
        }
        await MainActor.run { sending = true; sendError = nil }
        defer { Task { @MainActor in sending = false; selectedPhotoItem = nil } }
        do {
            guard let imageData = try await item.loadTransferable(type: ChatImageDataTransfer.self) else {
                await MainActor.run { sendError = "Не удалось загрузить фото" }
                return
            }
            let jpegData = imageData.dataAsJpeg
            let uploadUrl = try await vkApi.getMessagesUploadServer(token: token, peerId: peerId)
            let (server, hash, photo) = try await vkApi.uploadOwnerPhotoToServer(uploadUrl: uploadUrl, imageData: jpegData)
            let saved = try await vkApi.saveMessagesPhoto(token: token, server: server, hash: hash, photo: photo)
            let attachment = "photo\(saved.ownerId)_\(saved.id)"
            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            let messageId = try await vkApi.sendMessage(token: token, peerId: peerId, message: text, randomId: Int.random(in: 1...Int.max), attachment: attachment)
            let fromId = messages.first(where: { ($0.out ?? 0) == 1 })?.fromId ?? 0
            let newMsg = VKMessage(id: messageId, fromId: fromId, peerId: peerId, date: Date(), text: text.isEmpty ? "[Фото]" : text, out: 1, readState: nil)
            await MainActor.run {
                inputText = ""
                messages.append(newMsg)
                totalCount += 1
            }
        } catch {
            await MainActor.run { sendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }
}

private struct ChatImageDataTransfer: Transferable {
    let data: Data
    var dataAsJpeg: Data {
        guard let ui = UIImage(data: data) else { return data }
        return ui.jpegData(compressionQuality: 0.9) ?? data
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in ChatImageDataTransfer(data: data) }
    }
}
