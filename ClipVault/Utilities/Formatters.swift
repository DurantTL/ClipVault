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

  static func safeFolderName(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
enum Log { static func info(_ msg: String) { print("[ClipVault] \(msg)") } }
