import Foundation
import os

struct ClipExportProgress: Equatable {
  var completed: Int
  var total: Int
  var currentFilename: String
}

struct ClipExportSummary: Equatable {
  var destination: URL
  var copiedCount = 0
  var skippedCount = 0
  var failedCount = 0
  var totalBytesCopied: Int64 = 0
  var failures: [String] = []
  /// How exported copies were verified ("size check" or "SHA256"), or nil when
  /// nothing was copied.
  var verificationMethod: String?

  var message: String {
    var parts = ["\(copiedCount) copied (\(FileSizeFormatterUtil.string(totalBytesCopied)))"]
    if copiedCount > 0, let verificationMethod { parts.append("verified by \(verificationMethod)") }
    if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
    if failedCount > 0 { parts.append("\(failedCount) failed") }
    return parts.joined(separator: ", ") + " → \(destination.path)"
  }
}

/// Copies verified project clips into an editor-ready folder. Copy only, never
/// move; destination conflicts get safe duplicate names; source cards are
/// never touched because only copied project media is eligible.
///
/// Each copy goes through the same streaming copy used by ingest (partial file,
/// then an atomic rename) and is verified against the project media before it
/// counts. A copy that fails verification is set aside with an `.unverified`
/// extension so an editor never imports it as good media; it is not deleted.
final class ClipExportService {
  private let security = SecurityScopedBookmarkManager()
  private let copier = StreamingCopyService()
  private let verifier = VerificationService()

  /// The verification mode chosen in Settings (fast size check unless changed).
  static var defaultVerificationMode: VerificationMode {
    VerificationMode(rawValue: UserDefaults.standard.string(forKey: "verificationMode") ?? "") ?? .fast
  }

  func copyClips(
    _ items: [(clip: Clip, mediaURL: URL)],
    to destination: URL,
    verificationMode: VerificationMode = ClipExportService.defaultVerificationMode,
    progress: @escaping @MainActor (ClipExportProgress) -> Void
  ) async -> ClipExportSummary {
    var summary = ClipExportSummary(destination: destination)
    let workID = await BackgroundWorkCoordinator.shared.begin(kind: .export, label: destination.lastPathComponent)
    // Task cancellation does not reach the detached copy task by itself.
    let cancelled = OSAllocatedUnfairLock(initialState: false)
    let copier = self.copier
    let verifier = self.verifier
    copier.isCancelled = { cancelled.withLock { $0 } }
    await security.withAccessAsync(to: destination) {
      for (index, item) in items.enumerated() {
        if Task.isCancelled { break }
        await progress(ClipExportProgress(completed: index, total: items.count, currentFilename: item.clip.currentFilename))
        guard FileManager.default.fileExists(atPath: item.mediaURL.path) else {
          summary.skippedCount += 1
          summary.failures.append("\(item.clip.currentFilename): file is missing")
          continue
        }
        let target = SafeFilename.uniqueURL(for: destination.appendingPathComponent(item.mediaURL.lastPathComponent))
        do {
          try SafeFilename.assertContained(target, in: destination)
          let size = Int64((try? item.mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int(item.clip.fileSize))
          _ = try await withTaskCancellationHandler {
            try await copier.copy(from: item.mediaURL, to: target, alreadyCopiedBytes: 0, totalBytes: size) { _ in }
          } onCancel: {
            cancelled.withLock { $0 = true }
          }
          do {
            let outcome = try await verifier.verify(source: item.mediaURL, destination: target, mode: verificationMode)
            summary.copiedCount += 1
            summary.totalBytesCopied += item.clip.fileSize
            summary.verificationMethod = outcome.checksum == nil ? "size check" : "SHA256"
          } catch {
            let setAside = ClipExportService.setAsideUnverified(target)
            summary.failedCount += 1
            summary.failures.append(
              "\(item.clip.currentFilename): copy did not verify (\(error.localizedDescription)); kept as \(setAside.lastPathComponent)")
          }
        } catch is CancellationError {
          ClipExportService.removePartial(for: target)
          break
        } catch {
          ClipExportService.removePartial(for: target)
          summary.failedCount += 1
          summary.failures.append("\(item.clip.currentFilename): \(error.localizedDescription)")
        }
      }
      await progress(ClipExportProgress(completed: items.count, total: items.count, currentFilename: ""))
    }
    await BackgroundWorkCoordinator.shared.finish(workID)
    return summary
  }

  /// Renames a copy that failed verification to `<name>.unverified` (with a safe
  /// `_1`, `_2` suffix if needed) so an editor never imports it as good media.
  /// The file is kept, not deleted. Returns where it ended up.
  static func setAsideUnverified(_ target: URL) -> URL {
    let setAside = SafeFilename.uniqueURL(for: target.appendingPathExtension("unverified"))
    do {
      try FileManager.default.moveItem(at: target, to: setAside)
      return setAside
    } catch {
      return target
    }
  }

  /// Clears the temporary partial file and manifest a canceled or failed copy
  /// leaves next to the target, so nothing stray sits in the editor's folder.
  private static func removePartial(for target: URL) {
    try? FileManager.default.removeItem(at: StreamingCopyService.partialURL(for: target))
    try? FileManager.default.removeItem(at: StreamingCopyService.partialManifestURL(for: target))
  }
}
