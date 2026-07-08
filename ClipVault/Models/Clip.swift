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
  var createdAt: Date?
  var verificationStatus: VerificationStatus = .pending
  var cullStatus: CullStatus = .unrated
  var assignedFolder: String?
  var thumbnailPath: String?
  var errorMessage: String?
  var previewUnavailable: Bool = false

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
