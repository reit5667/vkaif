import AVFoundation
import Combine
import MediaPlayer

/// Singleton для воспроизведения аудио: фоновый режим, lock screen controls.
final class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published var currentTrack: VKAudio? = nil
    @Published var isPlaying = false
    @Published var progress: Double = 0

    private var player: AVPlayer? = nil
    private var progressTimer: Timer? = nil
    private var sessionConfigured = false

    private init() {}

    func play(_ track: VKAudio) {
        guard let urlStr = track.url, !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        configureSessionIfNeeded()
        stopTimer()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        currentTrack = track
        isPlaying = true
        progress = 0
        newPlayer.play()
        startTimer(duration: track.duration)
        updateNowPlaying(track: track)
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            if let track = currentTrack { startTimer(duration: track.duration) }
        }
        updateNowPlayingPlaybackState()
    }

    func stop() {
        player?.pause()
        player = nil
        currentTrack = nil
        isPlaying = false
        progress = 0
        stopTimer()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }

    private func updateNowPlaying(track: VKAudio) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let cur = player?.currentTime().seconds, !cur.isNaN {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = cur
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func startTimer(duration: Int) {
        let dur = Double(max(duration, 1))
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let cur = self.player?.currentTime().seconds ?? 0
            if cur.isNaN || cur < 0 { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { timer.invalidate(); return }
                self.progress = min(cur / dur, 1.0)
                if self.progress >= 1.0 {
                    timer.invalidate()
                    self.progressTimer = nil
                    self.isPlaying = false
                    self.progress = 0
                }
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
