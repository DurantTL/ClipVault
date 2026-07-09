import AppKit
import Foundation

/// Keeps recently visible JPEG thumbnails decoded in memory. SwiftUI can
/// recompute a card frequently while scrolling, selecting, or changing a
/// filter; decoding the same image from disk in `body` makes that work visible
/// as grid hitching. The modification date is part of the key so regeneration
/// naturally replaces a cached image.
final class ThumbnailImageCache {
  static let shared = ThumbnailImageCache()

  private let cache = NSCache<NSString, NSImage>()

  private init() {
    cache.countLimit = 400
  }

  func image(for url: URL) -> NSImage? {
    let key = cacheKey(for: url)
    if let image = cache.object(forKey: key) { return image }
    guard let image = NSImage(contentsOf: url) else { return nil }
    cache.setObject(image, forKey: key)
    return image
  }

  func removeAll() {
    cache.removeAllObjects()
  }

  private func cacheKey(for url: URL) -> NSString {
    let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    return "\(url.path)#\(date.timeIntervalSinceReferenceDate)" as NSString
  }
}
