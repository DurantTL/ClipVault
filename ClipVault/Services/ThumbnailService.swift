import AVFoundation
import AppKit
import Foundation

actor ThumbnailService {
  private let security = SecurityScopedBookmarkManager()
  func generate(for clip: Clip, projectFolder: URL, quality: ThumbnailQuality) async throws
    -> String
  {
    try await security.withAccessAsync(to: projectFolder) {
      let cache = projectFolder.appendingPathComponent(
        ".clipvault-cache/thumbnails", isDirectory: true)
      try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
      let dest = cache.appendingPathComponent(clip.id.uuidString).appendingPathExtension("jpg")
      if FileManager.default.fileExists(atPath: dest.path) { return dest.path }
      let sourceURL = URL(fileURLWithPath: clip.currentPath)
      return try await security.withAccessAsync(to: sourceURL) {
        let asset = AVURLAsset(url: sourceURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: quality.maxPixelSize, height: quality.maxPixelSize)
        let duration = try await asset.load(.duration)
        guard duration.isValid, !duration.isIndefinite, duration.seconds.isFinite,
          duration.seconds > 0
        else { throw CocoaError(.fileReadCorruptFile) }
        let seconds = min(max(0, duration.seconds * 0.10), max(0, duration.seconds - 0.05))
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let cg = try await gen.image(at: time).image
        guard
          let data = NSBitmapImageRep(cgImage: cg).representation(
            using: .jpeg, properties: [.compressionFactor: 0.82])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: dest, options: .atomic)
        return dest.path
      }
    }
  }
}
