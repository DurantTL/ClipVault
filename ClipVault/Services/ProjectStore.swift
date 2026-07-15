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
  /// Loads a recent project by its stored path.
  ///
  /// Pass `mountIfNeeded: false` for display/scan paths (e.g. building the
  /// Home screen list) so a project on a disconnected network drive is skipped
  /// quickly instead of blocking while macOS tries to mount the volume. The
  /// default (`true`) is used when the user explicitly opens a project.
  func loadRecent(path: String, mountIfNeeded: Bool = true) throws -> ClipVaultProject {
    let bookmarks =
      UserDefaults.standard.dictionary(forKey: "recentProjectBookmarks") as? [String: Data] ?? [:]
    if let data = bookmarks[path], let folder = try? security.resolve(data, mountIfNeeded: mountIfNeeded) {
      return try load(from: folder, mountIfNeeded: mountIfNeeded)
    }
    return try load(from: URL(fileURLWithPath: path), mountIfNeeded: mountIfNeeded)
  }
  func load(from folderOrFile: URL, mountIfNeeded: Bool = true) throws -> ClipVaultProject {
    try security.withAccess(to: folderOrFile) {
      let url =
        folderOrFile.lastPathComponent == Self.metadataName
        ? folderOrFile : folderOrFile.appendingPathComponent(Self.metadataName)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(
          domain: "ClipVault", code: 10,
          userInfo: [
            NSLocalizedDescriptionKey:
              "\(AppBrand.appName) could not find the project file. If this project is on an external drive or NAS, make sure it is connected and mounted."
          ])
      }
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601
      var p = try dec.decode(ClipVaultProject.self, from: Data(contentsOf: url))
      if let data = p.projectFolderBookmarkData,
        let resolved = try? security.resolve(data, mountIfNeeded: mountIfNeeded) {
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

  /// Loads the recent-project records that are currently readable. Disconnected
  /// drives and unavailable NAS projects are skipped so Preflight remains useful.
  func loadAll() throws -> [ClipVaultProject] {
    let paths = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
    return paths.compactMap { path in
      try? loadRecent(path: path, mountIfNeeded: false)
    }
  }
}
