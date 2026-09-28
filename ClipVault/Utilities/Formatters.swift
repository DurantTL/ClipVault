import Foundation

enum FileSizeFormatterUtil {
  static func string(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
enum DurationFormatterUtil {
  static func string(_ seconds: Double?) -> String {
    guard let seconds else { return "--:--" }
    let s = Int(seconds.rounded())
    return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
  }
}
enum SafeFilename {
  static func uniqueURL(for desired: URL) -> URL {
    let fm = FileManager.default
    var index = 0
    while true {
      let candidate = numberedURL(for: desired, index: index)
      if !fm.fileExists(atPath: candidate.path) { return candidate }
      index += 1
    }
  }

  static func uniqueURL(for desired: URL, reserving reservedPaths: inout Set<String>) -> URL {
    let fm = FileManager.default
    var index = 0
    while true {
      let candidate = numberedURL(for: desired, index: index)
      let normalizedPath = candidate.standardizedFileURL.path
      if !fm.fileExists(atPath: candidate.path), !reservedPaths.contains(normalizedPath) {
        reservedPaths.insert(normalizedPath)
        return candidate
      }
      index += 1
    }
  }

  private static func numberedURL(for desired: URL, index: Int) -> URL {
    guard index > 0 else { return desired }
    let dir = desired.deletingLastPathComponent()
    let base = desired.deletingPathExtension().lastPathComponent
    let ext = desired.pathExtension
    let numbered = dir.appendingPathComponent("\(base)_\(index)")
    return ext.isEmpty ? numbered : numbered.appendingPathExtension(ext)
  }

  /// Lenient transform for names used inside file/folder names. Never returns a
  /// path separator or a traversal segment; may return "" (callers treat that as
  /// "no folder").
  static func safeFolderName(_ name: String) -> String {
    let cleaned = String(name.unicodeScalars.map { scalar -> Character in
      forbiddenScalars.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) ? "-" : Character(scalar)
    })
    return cleaned.trimmingCharacters(in: trimSet)
  }

  private static let forbiddenScalars = CharacterSet(charactersIn: "/\\:")
  private static let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
  private static let maxComponentBytes = 255

  /// Strict single entry point for user-supplied path components (project and
  /// shoot names). Rejects anything that could escape the selected destination.
  static func validatedComponent(_ raw: String, label: String = "Name") throws -> String {
    let normalized = raw.precomposedStringWithCanonicalMapping
    let trimmed = normalized.trimmingCharacters(in: trimSet)
    guard !trimmed.isEmpty else { throw PathValidationError.empty(label) }
    if trimmed.hasPrefix("~") { throw PathValidationError.invalidCharacters(label) }
    for scalar in trimmed.unicodeScalars
    where forbiddenScalars.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
      throw PathValidationError.invalidCharacters(label)
    }
    guard trimmed.utf8.count <= maxComponentBytes else { throw PathValidationError.tooLong(label) }
    return trimmed
  }

  /// Symlink-aware, case-insensitive containment check. `url` may not exist yet;
  /// its nearest existing ancestor is resolved instead.
  static func isContained(_ url: URL, in root: URL) -> Bool {
    let rootPath = resolvedPath(root)
    let path = resolvedPath(url)
    return path == rootPath || path.lowercased().hasPrefix((rootPath + "/").lowercased())
  }

  /// Throws `PathValidationError.escapesDestination` unless `url` resolves inside `root`.
  static func assertContained(_ url: URL, in root: URL) throws {
    guard isContained(url, in: root) else { throw PathValidationError.escapesDestination }
  }

  private static func resolvedPath(_ url: URL) -> String {
    var existing = url.standardizedFileURL
    var trailing: [String] = []
    while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
      trailing.insert(existing.lastPathComponent, at: 0)
      existing = existing.deletingLastPathComponent()
    }
    var resolved = existing.resolvingSymlinksInPath()
    for part in trailing { resolved.appendPathComponent(part) }
    let path = resolved.standardizedFileURL.path
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}

enum PathValidationError: LocalizedError, Equatable {
  case empty(String)
  case invalidCharacters(String)
  case tooLong(String)
  case escapesDestination

  var errorDescription: String? {
    switch self {
    case .empty(let label): return "\(label) can't be empty."
    case .invalidCharacters(let label):
      return "\(label) can't contain / \\ : control characters, or start with ~."
    case .tooLong(let label): return "\(label) is too long."
    case .escapesDestination: return "That name would place files outside the chosen destination."
    }
  }
}
enum Log {
  static func info(_ msg: String) { print("[\(AppBrand.appName)] \(msg)") }
  /// Verbose preview diagnostics; off unless `defaults write <bundle id> previewDebugLogging -bool YES`.
  static var previewDebugEnabled: Bool { UserDefaults.standard.bool(forKey: "previewDebugLogging") }
}
