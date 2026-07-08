import CoreTransferable
import Foundation
import UniformTypeIdentifiers

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

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
