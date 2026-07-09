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
  var selected = true
  var url: URL
  var filename: String
  var fileSize: Int64
  var createdAt: Date?
  var modifiedAt: Date?
  var duration: Double?
  var cameraType: String
  var sourceRelativePath: String
  var sessionID: UUID?
  var previewThumbnailPath: String?
  var previewThumbnailStatus: ThumbnailStatus = .pending
  var previewThumbnailErrorMessage: String?

  enum CodingKeys: String, CodingKey {
    case id
    case selected
    case url
    case filename
    case fileSize
    case createdAt
    case modifiedAt
    case duration
    case cameraType
    case sourceRelativePath
    case sessionID
    case previewThumbnailPath
    case previewThumbnailStatus
    case previewThumbnailErrorMessage
  }

  init(
    id: UUID = UUID(),
    selected: Bool = true,
    url: URL,
    filename: String,
    fileSize: Int64,
    createdAt: Date?,
    modifiedAt: Date?,
    duration: Double?,
    cameraType: String,
    sourceRelativePath: String,
    sessionID: UUID? = nil,
    previewThumbnailPath: String? = nil,
    previewThumbnailStatus: ThumbnailStatus = .pending,
    previewThumbnailErrorMessage: String? = nil
  ) {
    self.id = id
    self.selected = selected
    self.url = url
    self.filename = filename
    self.fileSize = fileSize
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.duration = duration
    self.cameraType = cameraType
    self.sourceRelativePath = sourceRelativePath
    self.sessionID = sessionID
    self.previewThumbnailPath = previewThumbnailPath
    self.previewThumbnailStatus = previewThumbnailStatus
    self.previewThumbnailErrorMessage = previewThumbnailErrorMessage
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    selected = try container.decodeIfPresent(Bool.self, forKey: .selected) ?? true
    url = try container.decode(URL.self, forKey: .url)
    filename = try container.decode(String.self, forKey: .filename)
    fileSize = try container.decode(Int64.self, forKey: .fileSize)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
    duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    cameraType = try container.decode(String.self, forKey: .cameraType)
    sourceRelativePath = try container.decode(String.self, forKey: .sourceRelativePath)
    sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
    previewThumbnailPath = try container.decodeIfPresent(String.self, forKey: .previewThumbnailPath)
    previewThumbnailStatus = try container.decodeIfPresent(ThumbnailStatus.self, forKey: .previewThumbnailStatus) ?? .pending
    previewThumbnailErrorMessage = try container.decodeIfPresent(String.self, forKey: .previewThumbnailErrorMessage)
  }
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

  var selectedClips: [ScannedVideo] { clips.filter(\.selected) }
  var selectedClipCount: Int { selectedClips.count }
  var selectedSize: Int64 { selectedClips.reduce(0) { $0 + $1.fileSize } }
  var isPartiallySelected: Bool { selectedClipCount > 0 && selectedClipCount < clips.count }
}

enum IngestGroupingMode: String, CaseIterable, Identifiable {
  case date = "Group by Date"
  case dateAndGap = "Group by Date + Time Gap"
  case allFiles = "Show All Files"
  case sourceFolder = "Group by Source Folder"

  var id: String { rawValue }
}

enum IngestTimeGap: Int, CaseIterable, Identifiable {
  case thirty = 30
  case sixty = 60
  case ninety = 90
  case twoHours = 120

  var id: Int { rawValue }
  var label: String { rawValue == 120 ? "2 hours" : "\(rawValue) minutes" }
}

enum AlreadyImportedMode: String, CaseIterable, Identifiable {
  case skipAlreadyCopied = "Skip already copied"
  case retryFailedOnly = "Retry failed only"
  case includeAllSafeRename = "Include all with safe rename"

  var id: String { rawValue }
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
