import Foundation
import os

final class IngestService {
  let verifier = VerificationService()
  let metadata = MetadataService()
  let thumbnails = ThumbnailService()
  let store = ProjectStore()
  let security = SecurityScopedBookmarkManager()
  // Written from the main actor (UI) and read from the detached copy task,
  // so both flags must live behind a lock.
  let controlState = OSAllocatedUnfairLock(initialState: (cancelled: false, paused: false))
  let copyService = StreamingCopyService()
  var isCancelledNow: Bool { controlState.withLock { $0.cancelled } }
  var isPausedNow: Bool { controlState.withLock { $0.paused } }
  func cancel() { controlState.withLock { $0.cancelled = true } }
  func pause() { controlState.withLock { $0.paused = true } }
  func resume() { controlState.withLock { $0.paused = false } }
  func resetControlState() { controlState.withLock { $0 = (cancelled: false, paused: false) } }
}
