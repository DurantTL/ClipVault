import Foundation

final class ProjectStore {
  static let metadataName = AppBrand.metadataFileName
  private let security = SecurityScopedBookmarkManager()
  func save(_ project: ClipVaultProject) throws {
    let folder = security.projectFolderURL(for: project)
    try security.withAccess(to: folder) {
      let url = folder.appendingPathComponent(Self.metadataName)
      let enc = JSONEncoder()
      enc.outputFormatting = [.prettyPrinted, .sortedKeys]
      enc.dateEncodingStrategy = .iso8601
      try enc.encode(project).write(to: url, options: .atomic)
      addRecent(url)
    }
  }
  func loadRecent(path: String) throws -> ClipVaultProject {
    let bookmarks =
      UserDefaults.standard.dictionary(forKey: "recentProjectBookmarks") as? [String: Data] ?? [:]
    if let data = bookmarks[path], let folder = try? security.resolve(data) {
      return try load(from: folder)
    }
    return try load(from: URL(fileURLWithPath: path))
  }
  func load(from folderOrFile: URL) throws -> ClipVaultProject {
    try security.withAccess(to: folderOrFile) {
      let url =
        folderOrFile.lastPathComponent == Self.metadataName
        ? folderOrFile : folderOrFile.appendingPathComponent(Self.metadataName)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(
          domain: "ClipVault", code: 10,
          userInfo: [
            NSLocalizedDescriptionKey:
              "ClipVault could not find the project file. If this project is on an external drive or NAS, make sure it is connected and mounted."
          ])
      }
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601
      var p = try dec.decode(ClipVaultProject.self, from: Data(contentsOf: url))
      if let data = p.projectFolderBookmarkData, let resolved = try? security.resolve(data) {
        p.projectFolderPath = resolved.path
      }
      addRecent(url)
      return p
    }
  }
  func addRecent(_ url: URL) {
    var r = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
    r.removeAll { $0 == url.path }
    r.insert(url.path, at: 0)
    UserDefaults.standard.set(Array(r.prefix(10)), forKey: "recentProjects")
    if let data = try? security.bookmark(for: url.deletingLastPathComponent()) {
      var b =
        UserDefaults.standard.dictionary(forKey: "recentProjectBookmarks") as? [String: Data] ?? [:]
      b[url.path] = data
      UserDefaults.standard.set(b, forKey: "recentProjectBookmarks")
    }
  }
}
