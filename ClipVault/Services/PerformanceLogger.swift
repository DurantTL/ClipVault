import Foundation
import OSLog

struct PerformanceLogger {
  static let shared = PerformanceLogger()
  private let logger = Logger(subsystem: "com.clipvault.mac", category: "performance")

  func scan(duration: TimeInterval, fileCount: Int) {
    logger.info("Scan completed: files=\(fileCount, privacy: .public) duration=\(duration, format: .fixed(precision: 2), privacy: .public)s")
  }

  func thumbnail(duration: TimeInterval, failed: Bool) {
    logger.info("Thumbnail generated: duration=\(duration, format: .fixed(precision: 3), privacy: .public)s failed=\(failed, privacy: .public)")
  }

  func analysis(duration: TimeInterval, filename: String, failed: Bool) {
    logger.info("Analysis completed: file=\(filename, privacy: .public) duration=\(duration, format: .fixed(precision: 2), privacy: .public)s failed=\(failed, privacy: .public)")
  }

  func transferStarted(source: URL, destination: URL, resumedBytes: Int64) {
    logger.info("Transfer started: source=\(source.path, privacy: .public) destination=\(destination.path, privacy: .public) resumedBytes=\(resumedBytes, privacy: .public)")
  }

  func transfer(kind: String, bytes: Int64, duration: TimeInterval) {
    let mbps = duration > 0 ? (Double(bytes) / 1_048_576.0) / duration : 0
    logger.info("Transfer \(kind, privacy: .public): bytes=\(bytes, privacy: .public) speed=\(mbps, format: .fixed(precision: 1), privacy: .public) MiB/s")
  }

  func verification(mode: VerificationMode, bytes: Int64, duration: TimeInterval) {
    switch mode {
    case .fast:
      logger.info("Verification size check passed: bytes=\(bytes, privacy: .public)")
    case .strong:
      transfer(kind: "strong verification", bytes: bytes, duration: duration)
    }
  }

  func previewCacheCleared(fileCount: Int, bytes: Int64, path: String) {
    logger.info("Local ingest preview cache cleared: files=\(fileCount, privacy: .public) bytes=\(bytes, privacy: .public) path=\(path, privacy: .public)")
  }
}

enum VolumeCapacity {
  static func availableCapacity(for url: URL, fileManager: FileManager = .default) -> Int64? {
    let standardized = url.standardizedFileURL
    let basic = try? standardized.resourceValues(forKeys: [.volumeIsLocalKey, .volumeAvailableCapacityKey])
    let isLocal = basic?.volumeIsLocal ?? false
    let regular = basic?.volumeAvailableCapacity.map(Int64.init)

    let important: Int64?
    if isLocal {
      let values = try? standardized.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      important = values?.volumeAvailableCapacityForImportantUsage
    } else {
      important = nil
    }

    let attributes = try? fileManager.attributesOfFileSystem(forPath: standardized.path)
    let fileSystem = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    return preferredAvailableCapacity(
      isLocal: isLocal,
      important: important,
      regular: regular,
      fileSystem: fileSystem
    )
  }

  static func preferredAvailableCapacity(
    isLocal: Bool,
    important: Int64?,
    regular: Int64?,
    fileSystem: Int64?
  ) -> Int64? {
    if isLocal, let important { return important }
    return regular ?? fileSystem ?? important
  }
}