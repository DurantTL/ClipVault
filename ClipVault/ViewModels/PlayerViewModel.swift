import AVKit
import Foundation

final class PlayerViewModel: ObservableObject {
  @Published var player: AVPlayer?
  @Published var errorMessage: String?
  private let assetCache = NSCache<NSURL, AVURLAsset>()

  init() {
    assetCache.countLimit = 5
  }

  func load(url: URL, clip: Clip) {
    stop()
    errorMessage = nil
    let item = AVPlayerItem(asset: asset(for: url), automaticallyLoadedAssetKeys: ["playable", "tracks"])
    item.preferredForwardBufferDuration = 3
    player = AVPlayer(playerItem: item)
    logPreviewState(clip: clip, url: url, item: item)
  }

  /// Starts AVFoundation's local metadata work for adjacent clips while the
  /// current clip is playing. This keeps next/previous navigation responsive
  /// without reading source-card media or creating proxy files.
  func preload(urls: [URL]) {
    for url in urls {
      let asset = asset(for: url)
      asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) {}
    }
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

  private func asset(for url: URL) -> AVURLAsset {
    let key = url as NSURL
    if let asset = assetCache.object(forKey: key) { return asset }
    let asset = AVURLAsset(url: url)
    assetCache.setObject(asset, forKey: key)
    return asset
  }
}
