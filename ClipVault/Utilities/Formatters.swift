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
    if !fm.fileExists(atPath: desired.path) { return desired }
    let dir = desired.deletingLastPathComponent()
    let base = desired.deletingPathExtension().lastPathComponent
    let ext = desired.pathExtension
    var i = 1
    while true {
      let u = dir.appendingPathComponent("\(base)_\(i)").appendingPathExtension(ext)
      if !fm.fileExists(atPath: u.path) { return u }
      i += 1
    }
  }
  static func safeFolderName(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
enum Log { static func info(_ msg: String) { print("[ClipVault] \(msg)") } }
