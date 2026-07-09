import Foundation

struct AliasCreationSummary: Equatable {
  var folderName: String
  var aliasesFolder: URL
  var createdCount = 0
  var skippedCount = 0
  var failedCount = 0
  var failures: [String] = []

  var message: String {
    let noun = createdCount == 1 ? "alias" : "aliases"
    var parts = ["\(createdCount) \(noun) created"]
    if skippedCount > 0 { parts.append("\(skippedCount) already existed") }
    if failedCount > 0 { parts.append("\(failedCount) failed") }
    return parts.joined(separator: ", ") + " in Aliases/\(folderName)"
  }
}

/// Creates symbolic-link organization folders for copied project media. The
/// alias is never a source-card path, and deleting or replacing an alias never
/// changes the original copied file.
final class AliasService {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func aliasesFolder(in projectFolder: URL) -> URL {
    projectFolder.appendingPathComponent("Aliases", isDirectory: true)
  }

  func createAliases(named folderName: String, for items: [(clip: Clip, mediaURL: URL)], projectFolder: URL) -> AliasCreationSummary {
    let safeName = SafeFilename.safeFolderName(folderName)
    let folder = aliasesFolder(in: projectFolder).appendingPathComponent(safeName, isDirectory: true)
    var summary = AliasCreationSummary(folderName: safeName, aliasesFolder: folder)
    guard !safeName.isEmpty else {
      summary.failedCount = items.count
      summary.failures.append("An alias folder name is required.")
      return summary
    }

    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      summary.failedCount = items.count
      summary.failures.append("Could not create \(folder.path): \(error.localizedDescription)")
      return summary
    }

    for item in items {
      let desired = folder.appendingPathComponent(item.mediaURL.lastPathComponent)
      if existingAlias(for: item.mediaURL, desired: desired) != nil {
        summary.skippedCount += 1
        continue
      }
      do {
        try fileManager.createSymbolicLink(at: uniqueAliasURL(for: desired), withDestinationURL: item.mediaURL)
        summary.createdCount += 1
      } catch {
        summary.failedCount += 1
        summary.failures.append("\(item.clip.currentFilename): \(error.localizedDescription)")
      }
    }
    return summary
  }

  /// `fileExists` follows symlinks and misses a broken alias, which could make
  /// a new alias collide with it. Attributes see both regular files and links.
  private func itemExists(at url: URL) -> Bool {
    (try? fileManager.attributesOfItem(atPath: url.path)) != nil
  }

  private func existingAlias(for mediaURL: URL, desired: URL) -> URL? {
    guard itemExists(at: desired),
      let destination = try? fileManager.destinationOfSymbolicLink(atPath: desired.path) else { return nil }
    let resolved = URL(fileURLWithPath: destination, relativeTo: desired.deletingLastPathComponent())
    return resolved.standardizedFileURL.path == mediaURL.standardizedFileURL.path ? desired : nil
  }

  private func uniqueAliasURL(for desired: URL) -> URL {
    guard itemExists(at: desired) else { return desired }
    let directory = desired.deletingLastPathComponent()
    let base = desired.deletingPathExtension().lastPathComponent
    let ext = desired.pathExtension
    var index = 1
    while true {
      let candidate = directory.appendingPathComponent("\(base)_\(index)").appendingPathExtension(ext)
      if !itemExists(at: candidate) { return candidate }
      index += 1
    }
  }
}
