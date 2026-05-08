import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var currentFilePath: String?
    var onPlaybackStopped: (() -> Void)?

    func play(filePath: String) throws {
        if currentFilePath == filePath, player?.isPlaying == true {
            stop()
            return
        }

        let url = URL(fileURLWithPath: filePath)
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()

        guard player.play() else {
            throw AudioPlaybackError.failedToStart
        }

        self.player = player
        self.currentFilePath = filePath
    }

    func stop() {
        player?.stop()
        player = nil
        currentFilePath = nil
        onPlaybackStopped?()
    }

    var isPlaying: Bool {
        player?.isPlaying == true
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}

enum AudioPlaybackError: LocalizedError {
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Audio playback could not be started."
        }
    }
}
