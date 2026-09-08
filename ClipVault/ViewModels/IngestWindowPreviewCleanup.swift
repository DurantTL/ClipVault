import AppKit
import Foundation

final class IngestWindowPreviewCleanup: @unchecked Sendable {
  private let lock = NSLock()
  private var destinationRoot: URL?
  private var cleaned = false

  func update(destinationRoot: URL?) {
    lock.lock()
    self.destinationRoot = destinationRoot
    cleaned = false
    lock.unlock()
  }

  func cleanIfNeeded() {
    lock.lock()
    guard !cleaned else {
      lock.unlock()
      return
    }
    cleaned = true
    let destinationRoot = self.destinationRoot
    lock.unlock()

    if StoragePreferences.sourcePreviewCleanupPolicy == .whenIngestWindowCloses {
      IngestPreviewThumbnailService().cleanCache(destinationRoot: destinationRoot)
    }
  }

  deinit {
    cleanIfNeeded()
  }
}
