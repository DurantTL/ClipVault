import AVFoundation
import AppKit
import Foundation

final class IngestPreviewThumbnailService {
  struct Result: Sendable {
    let path: String
    let duration: Double?
  }

  private let security = SecurityScopedBookmarkManager()

  func cacheDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let cache = base
      .appendingPathComponent(AppBrand.previewCacheFolderName, isDirectory: true)
      .appendingPathComponent("IngestPreviewThumbnails", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    return cache
  }

  func cleanCache() {
    do {
      let cache = try cacheDirectory()
      let contents = try FileManager.default.contentsOfDirectory(
        at: cache,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
      var removedFiles = 0
      var removedBytes: Int64 = 0
      for url in contents {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        do {
          try FileManager.default.removeItem(at: url)
          removedFiles += 1
          removedBytes += size
        } catch {
          print("ClipVault ingest preview thumbnail cleanup failure: file=\(url.path), error=\(error.localizedDescription)")
        }
      }
      PerformanceLogger.shared.previewCacheCleared(
        fileCount: removedFiles,
        bytes: removedBytes,
        path: cache.path
      )
    } catch {
      print("ClipVault ingest preview thumbnail cleanup failure: error=\(error.localizedDescription)")
    }
  }

  func generate(for clip: ScannedVideo, sourceRoot: URL, maxPixelSize: CGFloat = 360) async throws -> Result {
    try await security.withAccessAsync(to: sourceRoot) {
      let cache = try self.cacheDirectory()
      let dest = cache.appendingPathComponent(clip.id.uuidString).appendingPathExtension("jpg")
      if FileManager.default.fileExists(atPath: dest.path) {
        return Result(path: dest.path, duration: clip.duration)
      }

      let asset = AVURLAsset(url: clip.url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
      generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
      generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

      let duration = try? await asset.load(.duration)
      let seconds = self.thumbnailSeconds(for: duration)
      let time = CMTime(seconds: seconds, preferredTimescale: 600)

      do {
        let start = Date()
        let cgImage = try await generator.image(at: time).image
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(
          using: .jpeg,
          properties: [.compressionFactor: 0.78]
        ) else {
          throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: dest, options: .atomic)
        PerformanceLogger.shared.thumbnail(duration: Date().timeIntervalSince(start), failed: false)
        return Result(path: dest.path, duration: duration?.seconds)
      } catch {
        PerformanceLogger.shared.thumbnail(duration: 0, failed: true)
        let exists = FileManager.default.fileExists(atPath: clip.url.path)
        print("""
        ClipVault ingest preview thumbnail failure: filename=\(clip.filename), sourceURL=\(clip.url.path), sourceFileExists=\(exists), assetDuration=\(duration?.seconds.description ?? "nil"), requestedFrameTime=\(seconds), error=\(error.localizedDescription)
        """)
        throw error
      }
    }
  }

  private func thumbnailSeconds(for duration: CMTime?) -> Double {
    guard let duration, duration.isValid, !duration.isIndefinite, duration.seconds.isFinite, duration.seconds > 0 else {
      return 1.0
    }
    if duration.seconds < 1.0 {
      return min(0.1, max(0.0, duration.seconds * 0.5))
    }
    return min(max(duration.seconds * 0.10, 0.1), max(0.0, duration.seconds - 0.05))
  }
}