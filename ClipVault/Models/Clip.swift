import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum AnalysisStatus: String, Codable, CaseIterable {
  case notAnalyzed
  case analyzing
  case complete
  case failed
  case canceled

  var label: String {
    switch self {
    case .notAnalyzed: return "Not Analyzed"
    case .analyzing: return "Analyzing"
    case .complete: return "Complete"
    case .failed: return "Failed Analysis"
    case .canceled: return "Canceled"
    }
  }
}

struct Clip: Identifiable, Codable, Equatable, Transferable {
  var id = UUID()
  var originalSourcePath: String
  var originalFilename: String
  var currentPath: String
  var currentFilename: String
  var relativePath: String
  var fileSize: Int64
  var duration: Double?
  var width: Int?
  var height: Int?
  var frameRate: Double?
  var codec: String?
  var bitDepth: Int?
  var hasAudio: Bool?
  var audioChannelCount: Int?
  var orientation: String?
  var estimatedBitrate: Double?
  var createdAt: Date?
  var modifiedAt: Date?
  var ingestDate: Date?
  var sonyCardFolderPath: String?
  var cardVolumeName: String?
  var checksum: String?
  var verificationStatus: VerificationStatus = .pending
  var cullStatus: CullStatus = .unrated
  var assignedFolder: String?
  var thumbnailPath: String?
  var errorMessage: String?
  var previewUnavailable: Bool = false

  var title: String = ""
  var description: String = ""
  var productionTags: [String] = []
  var people: [String] = []
  var location: String = ""
  var scene: String = ""
  var shotType: String = ""
  var camera: String = ""
  var lens: String = ""
  var audioNotes: String = ""
  var transcriptNotes: String = ""
  var usageNotes: String = ""
  var colorLabel: String = ""
  var favorite: Bool = false
  var isBroll: Bool = false
  var isSermon: Bool = false
  var isInterview: Bool = false
  var isSocialClipCandidate: Bool = false
  var customNotes: String = ""
  var automaticTags: [String] = []
  var analysisStatus: AnalysisStatus = .notAnalyzed
  var focusScore: Double?
  var focusConfidence: Double?
  var sampledFrameCount: Int?
  var focusWarning: Bool = false
  var maxFaceCount: Int?
  var averageFaceCount: Double?
  var hasFaces: Bool = false
  var hasCloseFace: Bool = false
  var faceVisibilityScore: Double?
  var uniqueFaceAppearanceCount: Int?
  var stabilityScore: Double?
  var possiblyShaky: Bool = false
  var brightnessScore: Double?
  var contrastScore: Double?


  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
