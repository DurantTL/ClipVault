import Foundation

struct SourceVideo: Identifiable, Hashable {
  var id = UUID()
  let url: URL
  let relativePath: String
  let size: Int64
  let createdAt: Date?
}

struct IngestProgress: Equatable {
  var currentFilename = ""
  var currentIndex = 0
  var totalCount = 0
  var copiedBytes: Int64 = 0
  var totalBytes: Int64 = 0
  var bytesPerSecond: Double = 0
  var message = "Ready"
  var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(copiedBytes) / Double(totalBytes)) }
}
