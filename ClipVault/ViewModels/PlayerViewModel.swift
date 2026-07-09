import AVKit
import Foundation

final class PlayerViewModel: ObservableObject {
  @Published var player: AVPlayer?
  @Published var errorMessage: String?

  func load(url: URL, clip: Clip) {
    stop()
    errorMessage = nil
    let item = AVPlayerItem(url: url)
    player = AVPlayer(playerItem: item)
    logPreviewState(clip: clip, url: url, item: item)
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

  private func logPreviewState(clip: Clip, url: URL, item: AVPlayerItem) {
    let exists = FileManager.default.fileExists(atPath: url.path)
    if let error = item.error {
      errorMessage = error.localizedDescription
    }
    print("""
    ClipVault preview load: filename=\(clip.currentFilename), resolvedURL=\(url.path), fileExists=\(exists), copyStatus=\(clip.copyStatus.rawValue), verificationStatus=\(clip.verificationStatus.rawValue), thumbnailStatus=\(clip.thumbnailStatus.rawValue), avPlayerError=\(item.error?.localizedDescription ?? "none")
    """)
  }
}
