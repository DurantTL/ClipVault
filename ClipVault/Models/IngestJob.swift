import Foundation

struct SourceVideo: Identifiable, Hashable, Codable {
  var id = UUID()
  let url: URL
  let relativePath: String
  let size: Int64
  let createdAt: Date?
  let modifiedAt: Date?
  let sonyCardFolderPath: String?
  let cardType: String
}

struct ScannedVideo: Identifiable, Hashable, Codable {
  var id = UUID()
  var url: URL
  var filename: String
  var fileSize: Int64
  var createdAt: Date?
  var modifiedAt: Date?
  var duration: Double?
  var cameraType: String
  var sourceRelativePath: String
  var sessionID: UUID?
}

struct IngestSession: Identifiable, Hashable, Codable {
  var id = UUID()
  var title: String
  var date: Date
  var startTime: Date
  var endTime: Date
  var clips: [ScannedVideo]
  var totalSize: Int64
  var selected: Bool = true
  var thumbnailPreviewPaths: [String] = []
  var cameraType: String
  var sourceVolumeName: String
}


struct IngestProgress: Equatable {
  var currentFilename = ""
  var currentIndex = 0
  var totalCount = 0
  var copiedBytes: Int64 = 0
  var totalBytes: Int64 = 0
  var bytesPerSecond: Double = 0
  var message = "Ready"
  var backupMessage = "Primary only"
  var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(copiedBytes) / Double(totalBytes)) }
}
