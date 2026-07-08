import AVKit
import Foundation

final class PlayerViewModel: ObservableObject {
  @Published var player: AVPlayer?

  func load(_ clip: Clip) {
    stop()
    player = AVPlayer(url: URL(fileURLWithPath: clip.currentPath))
  }

  func stop() {
    player?.pause()
    player = nil
  }

  func togglePlayPause() {
    guard let player else { return }
    if player.timeControlStatus == .playing {
      player.pause()
    } else {
      player.play()
    }
  }
}
