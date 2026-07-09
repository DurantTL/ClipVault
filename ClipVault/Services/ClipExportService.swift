import Foundation

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

  var message: String {
    var parts = ["\(copiedCount) copied (\(FileSizeFormatterUtil.string(totalBytesCopied)))"]
    if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
    if failedCount > 0 { parts.append("\(failedCount) failed") }
    return parts.joined(separator: ", ") + " → \(destination.path)"
  }
}

/// Copies verified project clips into an editor-ready folder. Copy only, never
/// move; destination conflicts get safe duplicate names; source cards are
/// never touched because only copied project media is eligible.
final class ClipExportService {
  private let security = SecurityScopedBookmarkManager()

  func copyClips(
    _ items: [(clip: Clip, mediaURL: URL)],
    to destination: URL,
    progress: @escaping @MainActor (ClipExportProgress) -> Void
  ) async -> ClipExportSummary {
    var summary = ClipExportSummary(destination: destination)
    let workID = await BackgroundWorkCoordinator.shared.begin(kind: .export, label: destination.lastPathComponent)
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
          try FileManager.default.copyItem(at: item.mediaURL, to: target)
          summary.copiedCount += 1
          summary.totalBytesCopied += item.clip.fileSize
        } catch {
          summary.failedCount += 1
          summary.failures.append("\(item.clip.currentFilename): \(error.localizedDescription)")
        }
      }
      await progress(ClipExportProgress(completed: items.count, total: items.count, currentFilename: ""))
    }
    await BackgroundWorkCoordinator.shared.finish(workID)
    return summary
  }
}
