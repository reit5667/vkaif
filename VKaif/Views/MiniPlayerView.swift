import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var audioService = AudioPlayerService.shared

    var body: some View {
        if let track = audioService.currentTrack {
            HStack(spacing: 12) {
                if let thumbStr = track.album?.thumb?.displayURL, let thumbURL = URL(string: thumbStr) {
                    AsyncImage(url: thumbURL) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color(.systemGray5) }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    audioService.togglePlayPause()
                } label: {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                Button {
                    audioService.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                if audioService.isPlaying || audioService.progress > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * audioService.progress, height: 2)
                    }
                    .frame(height: 2)
                }
            }
        }
    }
}
