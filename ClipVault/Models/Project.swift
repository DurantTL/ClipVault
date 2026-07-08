import Foundation

struct ClipVaultProject: Identifiable, Codable {
  var id = UUID()
  var name: String
  var createdAt = Date()
  var sourceBookmarkData: Data?
  var destinationBookmarkData: Data?
  var projectFolderBookmarkData: Data?
  var projectFolderPath: String
  var ingestIncomplete: Bool = false
  var customFolders: [String] = ["Sermon", "B-Roll", "Social Media", "Archive", "Review Later"]
  var clips: [Clip] = []
}
