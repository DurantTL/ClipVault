import AVFoundation
import AppKit
import Foundation

actor ThumbnailService {
  struct Result: Sendable {
    let path: String
    let relativePath: String
  }

  private let security = SecurityScopedBookmarkManager()

  func thumbnailURL(for clip: Clip, in project: ClipVaultProject) -> URL {
    let projectFolder = security.projectFolderURL(for: project)
    return projectFolder
      .appendingPathComponent(".clipvault-cache", isDirectory: true)
      .appendingPathComponent("thumbnails", isDirectory: true)
      .appendingPathComponent(clip.id.uuidString)
      .appendingPathExtension("jpg")
  }

  func existingThumbnailURL(for clip: Clip, in project: ClipVaultProject) -> URL? {
    if let stored = storedThumbnailURL(for: clip, in: project), FileManager.default.fileExists(atPath: stored.path) {
      return stored
    }

    let cacheURL = thumbnailURL(for: clip, in: project)
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      return cacheURL
    }

    return nil
  }

  func generate(
    for clip: Clip,
    mediaURL: URL,
    project: ClipVaultProject,
    quality: ThumbnailQuality
  ) async throws -> Result {
    let projectFolder = security.projectFolderURL(for: project)
    return try await security.withAccessAsync(to: projectFolder) {
      try await security.withAccessAsync(to: mediaURL) {
        let cache = projectFolder
          .appendingPathComponent(".clipvault-cache", isDirectory: true)
          .appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let dest = self.thumbnailURL(for: clip, in: project)
        if FileManager.default.fileExists(atPath: dest.path) {
          return Result(path: dest.path, relativePath: self.relativeThumbnailPath(for: dest, projectFolder: projectFolder))
        }

        let asset = AVURLAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: quality.maxPixelSize, height: quality.maxPixelSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let duration = try? await asset.load(.duration)
        let seconds = self.thumbnailSeconds(for: duration)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)

        do {
          let cgImage = try await generator.image(at: time).image
          guard let data = NSBitmapImageRep(cgImage: cgImage).representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
          ) else {
            throw CocoaError(.fileWriteUnknown)
          }
          try data.write(to: dest, options: .atomic)
          return Result(path: dest.path, relativePath: self.relativeThumbnailPath(for: dest, projectFolder: projectFolder))
        } catch {
          let exists = FileManager.default.fileExists(atPath: mediaURL.path)
          print("""
          ClipVault thumbnail failure: filename=\(clip.currentFilename), resolvedMediaURL=\(mediaURL.path), mediaFileExists=\(exists), cacheThumbnailURL=\(dest.path), assetDuration=\(duration?.seconds.description ?? "nil"), requestedThumbnailTime=\(seconds), error=\(error.localizedDescription)
          """)
          throw error
        }
      }
    }
  }

  private func storedThumbnailURL(for clip: Clip, in project: ClipVaultProject) -> URL? {
    guard let path = clip.thumbnailPath, !path.isEmpty else { return nil }
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return security.projectFolderURL(for: project).appendingPathComponent(path)
  }

  private func relativeThumbnailPath(for url: URL, projectFolder: URL) -> String {
    let prefix = projectFolder.path + "/"
    if url.path.hasPrefix(prefix) {
      return String(url.path.dropFirst(prefix.count))
    }
    return url.path
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
