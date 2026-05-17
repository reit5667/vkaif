import SwiftUI

struct StickerPickerView: View {
    let authService: AuthService
    let onSend: (Int) -> Void

    @State private var packs: [VKStickerPack] = []
    @State private var selectedPack: VKStickerPack? = nil
    @State private var loadState: LoadState = .loading
    @Environment(\.dismiss) private var dismiss

    private let vkApi = VKApiService()
    enum LoadState { case loading, loaded, failed }

    var body: some View {
        VStack(spacing: 0) {
            switch loadState {
            case .loading:
                ProgressView("Загрузка стикеров…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                Text("Не удалось загрузить стикеры")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if packs.isEmpty {
                    Text("Стикеры не найдены")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    stickerContent
                }
            }
        }
        .task { await loadStickers() }
    }

    private var stickerContent: some View {
        VStack(spacing: 0) {
            if let pack = selectedPack ?? packs.first, let stickers = pack.stickers, !stickers.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(stickers) { sticker in
                            Button {
                                onSend(sticker.stickerId)
                                dismiss()
                            } label: {
                                if let urlStr = sticker.displayURL, let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFit()
                                        } else {
                                            Color(.systemGray5)
                                        }
                                    }
                                    .frame(width: 60, height: 60)
                                } else {
                                    Color(.systemGray5).frame(width: 60, height: 60)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }

            if packs.count > 1 {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(packs) { pack in
                            Button {
                                selectedPack = pack
                            } label: {
                                Text(pack.title ?? "Пак")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedPack?.id == pack.id ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(selectedPack?.id == pack.id ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func loadStickers() async {
        guard let token = authService.accessToken else { loadState = .failed; return }
        do {
            let result = try await vkApi.getStickers(token: token)
            packs = result
            selectedPack = result.first
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}
