import Foundation

struct ClipVaultProject: Identifiable, Codable {
  var id = UUID()
  var name: String
  var createdAt = Date()
  var lastOpenedAt: Date?
  var sourceBookmarkData: Data?
  var destinationBookmarkData: Data?
  var projectFolderBookmarkData: Data?
  var projectFolderPath: String
  var ingestIncomplete: Bool = false
  var customFolders: [String] = ["Sermon", "B-Roll", "Social Media", "Archive", "Review Later"]
  var clips: [Clip] = []

  var projectTitle: String = ""
  var productionName: String = ""
  var clientOrOrganization: String = ""
  var eventName: String = ""
  var eventDate: Date?
  var location: String = ""
  var cameraOperator: String = ""
  var cameraModel: String = ""
  var notes: String = ""
  var defaultTags: [String] = []
}
