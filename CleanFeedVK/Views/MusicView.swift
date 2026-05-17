import SwiftUI
import AVFoundation

struct MusicView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject private var audioService = AudioPlayerService.shared

    @State private var tracks: [VKAudio] = []
    @State private var totalCount: Int = 0
    @State private var loadState: LoadState = .idle
    @State private var isLoadingMore = false
    @State private var currentUserId: Int? = nil

    private let vkApi = VKApiService()
    private let pageSize = 100

    enum LoadState { case idle, loading, loaded, failed(String) }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .idle, .loading where tracks.isEmpty:
                    ProgressView("Загрузка музыки…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let msg):
                    VStack(spacing: 12) {
                        Text(msg).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Повторить") { Task { await load(reset: true) } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    trackList
                }
            }
            .navigationTitle("Музыка")
            .task { if tracks.isEmpty { await load(reset: true) } }
        }
    }

    private var trackList: some View {
        List {
            ForEach(tracks) { track in
                trackRow(track)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .onAppear {
                        if track.id == tracks.last?.id && tracks.count < totalCount {
                            Task { await load(reset: false) }
                        }
                    }
            }
            if isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func trackRow(_ track: VKAudio) -> some View {
        let isCurrentTrack = audioService.currentTrack?.id == track.id
        let isPlaying = isCurrentTrack && audioService.isPlaying
        HStack(spacing: 12) {
            ZStack {
                if let thumbStr = track.album?.thumb?.displayURL, let thumbURL = URL(string: thumbStr) {
                    AsyncImage(url: thumbURL) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color(.systemGray5) }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                }
                if isCurrentTrack {
                    Color.black.opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isCurrentTrack ? Color.accentColor : Color.primary)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isCurrentTrack {
                    ProgressView(value: audioService.progress)
                        .tint(Color.accentColor)
                }
            }

            Spacer()

            Text(formatDuration(track.duration))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrentTrack {
                audioService.togglePlayPause()
            } else {
                audioService.play(track)
            }
        }
    }

    private func load(reset: Bool) async {
        guard let token = authService.accessToken, !token.isEmpty else { return }
        if currentUserId == nil {
            if let users = try? await vkApi.getUsers(token: token), let first = users.first {
                currentUserId = first.id
            }
        }
        guard let userId = currentUserId else {
            loadState = .failed("Не удалось получить ID пользователя")
            return
        }
        if reset {
            loadState = .loading
            tracks = []
            totalCount = 0
        } else {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }
        do {
            let response = try await vkApi.getAudio(token: token, ownerId: userId, offset: tracks.count, count: pageSize)
            if reset {
                tracks = response.items
            } else {
                tracks.append(contentsOf: response.items)
            }
            totalCount = response.count
            loadState = .loaded
        } catch {
            if reset {
                loadState = .failed(error.localizedDescription)
            }
        }
        isLoadingMore = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
