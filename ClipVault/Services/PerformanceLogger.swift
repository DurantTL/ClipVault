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

  func transfer(kind: String, bytes: Int64, duration: TimeInterval) {
    let mbps = duration > 0 ? (Double(bytes) / 1_048_576.0) / duration : 0
    logger.info("Transfer \(kind, privacy: .public): bytes=\(bytes, privacy: .public) speed=\(mbps, format: .fixed(precision: 1), privacy: .public) MiB/s")
  }
}
