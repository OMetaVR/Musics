import AVFoundation
import MediaPlayer
import UIKit
import MusicsCore

/// Lock screen, Control Center, headphones, CarPlay-style remote commands, and the audio session.
@MainActor
final class NowPlayingCenter {
    weak var controller: PlaybackController?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?

    func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opts = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                switch type {
                case .began:
                    self?.controller?.interruptionBegan()
                case .ended:
                    let resume = opts.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                    self?.controller?.interruptionEnded(shouldResume: resume)
                @unknown default: break
                }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                // Headphones unplugged / AirPods out: pause, as every music app does.
                if raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable {
                    self?.controller?.pause()
                }
            }
        }
    }

    func activate() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Remote command handlers run on the main thread.
    private func on(_ command: MPRemoteCommand,
                    _ action: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        command.isEnabled = true
        command.addTarget { event in MainActor.assumeIsolated { action(event) } }
    }

    func configureCommands() {
        let c = MPRemoteCommandCenter.shared()
        on(c.playCommand) { [weak self] _ in self?.controller?.play(); return .success }
        on(c.pauseCommand) { [weak self] _ in self?.controller?.pause(); return .success }
        on(c.togglePlayPauseCommand) { [weak self] _ in self?.controller?.togglePlay(); return .success }
        on(c.nextTrackCommand) { [weak self] _ in self?.controller?.next(); return .success }
        on(c.previousTrackCommand) { [weak self] _ in self?.controller?.previous(); return .success }
        on(c.changePlaybackPositionCommand) { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.controller?.seek(to: e.positionTime)
            return .success
        }
        on(c.changeRepeatModeCommand) { [weak self] e in
            guard let e = e as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode = e.repeatType == .one ? .one : e.repeatType == .all ? .all : .off
            self?.controller?.setRepeat(mode)
            return .success
        }
        on(c.changeShuffleModeCommand) { [weak self] e in
            guard let e = e as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            self?.controller?.setShuffle(e.shuffleType != .off)
            return .success
        }
        c.likeCommand.localizedTitle = "Like"
        on(c.likeCommand) { [weak self] _ in self?.controller?.toggleLikeCurrent(); return .success }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    /// Full update: call when the track changes.
    func update(track: Track?, artworkURL: URL?, position: Double, duration: Double, playing: Bool, liked: Bool,
                repeatMode: RepeatMode, shuffle: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyAlbumArtist: track.albumArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if track.trackNumber > 0 { info[MPMediaItemPropertyAlbumTrackNumber] = track.trackNumber }
        if artworkURL == lastArtworkURL, let art = center.nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = art
        }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
        MPRemoteCommandCenter.shared().likeCommand.isActive = liked
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType =
            repeatMode == .one ? .one : repeatMode == .all ? .all : .off
        MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = shuffle ? .items : .off

        guard let artworkURL, artworkURL != lastArtworkURL else { return }
        lastArtworkURL = artworkURL
        artworkTask?.cancel()
        artworkTask = Task {
            guard let image = await ArtworkLoader.shared.image(for: artworkURL), !Task.isCancelled else { return }
            let art = Self.artwork(image)
            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = art
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
    }

    /// MediaPlayer calls the artwork handler on a background queue, so build it outside the main actor.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Cheap update: position and rate only.
    func updateProgress(position: Double, duration: Double, playing: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }
}
