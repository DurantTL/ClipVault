import Foundation

enum DetectedCardType: String {
  case sony = "Sony Card"
  case canonDCF = "Canon/DCF Card"
  case generic = "Generic Folder"

  var summary: String {
    switch self {
    case .sony: return "Sony card detected: scanning PRIVATE/M4ROOT/CLIP"
    case .canonDCF: return "Canon/DCF card detected: scanning DCIM"
    case .generic: return "Generic folder: recursive scan"
    }
  }
}

final class SourceScanner {
  static let supported = Set(["mov", "mp4", "m4v", "mts", "m2ts", "mxf", "avi", "hevc", "h264", "crm"])
  static let ignoredSidecars = Set(["thm", "jpg", "jpeg", "cr3", "xmp", "xml", "cif", "bin"])
  private let security = SecurityScopedBookmarkManager()

  func detectCardType(source: URL) -> DetectedCardType {
    let fm = FileManager.default
    if fm.fileExists(atPath: source.appendingPathComponent("PRIVATE/M4ROOT/CLIP").path) {
      return .sony
    }
    if fm.fileExists(atPath: source.appendingPathComponent("DCIM").path) {
      return .canonDCF
    }
    return .generic
  }

  func scan(source: URL, includeProxyFiles: Bool) throws -> [SourceVideo] {
    try security.withAccess(to: source) {
      let fm = FileManager.default
      let cardType = detectCardType(source: source)
      let sonyClip = source.appendingPathComponent("PRIVATE/M4ROOT/CLIP")
      let sonySub = source.appendingPathComponent("PRIVATE/M4ROOT/SUB")
      let dcim = source.appendingPathComponent("DCIM")
      var roots: [URL] = []
      switch cardType {
      case .sony:
        roots.append(sonyClip)
        if includeProxyFiles && fm.fileExists(atPath: sonySub.path) { roots.append(sonySub) }
      case .canonDCF:
        roots.append(dcim)
      case .generic:
        roots.append(source)
      }
      var out: [SourceVideo] = []
      for root in roots {
        guard
          let e = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isHiddenKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { continue }
        for case let url as URL in e {
          if !includeProxyFiles && url.standardizedFileURL.path.contains("/PRIVATE/M4ROOT/SUB/") {
            continue
          }
          let ext = url.pathExtension.lowercased()
          if Self.ignoredSidecars.contains(ext) { continue }
          guard Self.supported.contains(ext) else { continue }
          let rv = try url.resourceValues(forKeys: [.isHiddenKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
          if rv.isHidden == true || url.lastPathComponent.hasPrefix(".") { continue }
          let relBase = source.standardizedFileURL.path
          let rel = url.standardizedFileURL.path.replacingOccurrences(of: relBase + "/", with: "")
          out.append(
            SourceVideo(
              url: url,
              relativePath: rel,
              size: Int64(rv.fileSize ?? 0),
              createdAt: rv.creationDate,
              modifiedAt: rv.contentModificationDate,
              sonyCardFolderPath: cardType == .sony ? sonyClip.path : nil,
              cardType: cardType.rawValue
            ))
        }
      }
      return out.sorted {
        $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
      }
    }
  }
}
