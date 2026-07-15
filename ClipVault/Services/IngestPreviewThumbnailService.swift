import AVFoundation
import AppKit
import Foundation

final class IngestPreviewThumbnailService {
  struct Result: Sendable {
    let path: String
    let duration: Double?
  }

  private let security = SecurityScopedBookmarkManager()

  func cacheDirectory(destinationRoot: URL?) throws -> ResolvedStorageDirectory? {
    guard let storage = StoragePreferences.sourcePreviewDirectory(destinationRoot: destinationRoot) else {
      return nil
    }
    try security.withAccess(to: storage.accessURL) {
      try FileManager.default.createDirectory(
        at: storage.directoryURL,
        withIntermediateDirectories: true
      )
    }
    return storage
  }

  func cleanCache(destinationRoot: URL? = nil) {
    do {
      guard let storage = try cacheDirectory(destinationRoot: destinationRoot) else { return }
      let result = security.withAccess(to: storage.accessURL) {
        StoragePreferences.clearFolderContents(at: storage.directoryURL)
      }
      PerformanceLogger.shared.previewCacheCleared(
        fileCount: result.files,
        bytes: result.bytes,
        path: storage.directoryURL.path
      )
    } catch {
      print("ClipVault ingest preview thumbnail cleanup failure: error=\(error.localizedDescription)")
    }
  }

  func generate(
    for clip: ScannedVideo,
    sourceRoot: URL,
    destinationRoot: URL?,
    maxPixelSize: CGFloat = 360
  ) async throws -> Result {
    guard let storage = try cacheDirectory(destinationRoot: destinationRoot) else {
      throw NSError(
        domain: "ClipVault",
        code: 40,
        userInfo: [NSLocalizedDescriptionKey: "Source preview generation is disabled or its selected storage location is unavailable."]
      )
    }

    return try await security.withAccessAsync(to: sourceRoot) {
      try await security.withAccessAsync(to: storage.accessURL) {
        let cache = storage.directoryURL
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
        let seconds = ThumbnailTiming.seconds(for: duration)
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
          self.enforceCacheLimit(in: cache, preserving: dest)
          PerformanceLogger.shared.thumbnail(duration: Date().timeIntervalSince(start), failed: false)
          return Result(path: dest.path, duration: duration?.seconds)
        } catch {
          PerformanceLogger.shared.thumbnail(duration: 0, failed: true)
          let exists = FileManager.default.fileExists(atPath: clip.url.path)
          print("""
          ClipVault ingest preview thumbnail failure: filename=\(clip.filename), sourceURL=\(clip.url.path), sourceFileExists=\(exists), cacheThumbnailURL=\(dest.path), assetDuration=\(duration?.seconds.description ?? "nil"), requestedFrameTime=\(seconds), error=\(error.localizedDescription)
          """)
          throw error
        }
      }
    }
  }

  private func enforceCacheLimit(in directory: URL, preserving currentFile: URL) {
    let limit = StoragePreferences.sourcePreviewCacheLimitBytes
    guard limit > 0 else { return }
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    let entries: [(url: URL, size: Int64, date: Date)] = files.compactMap { url in
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
      guard values?.isRegularFile == true else { return nil }
      return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
    }
    var total = entries.reduce(Int64(0)) { $0 + $1.size }
    guard total > limit else { return }

    for entry in entries.sorted(by: { $0.date < $1.date }) where entry.url != currentFile {
      guard total > limit else { break }
      if (try? FileManager.default.removeItem(at: entry.url)) != nil {
        total -= entry.size
      }
    }
  }

}
