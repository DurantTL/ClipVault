import Foundation

/// One copied destination (primary or a verified backup root) for MHL export.
/// Paths must point at project/copied media - never source cards.
struct MHLDestination: Equatable, Sendable {
  var label: String
  var rootURL: URL
}

struct MHLExportOptions: Equatable, Sendable {
  var now: Date = Date()
  /// When nil, writes under `<project>/.clipvault-cache/reports/`.
  var outputDirectory: URL? = nil
  var hostname: String = ProcessInfo.processInfo.hostName
  var appVersion: String =
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
}

struct MHLExportFileSummary: Equatable, Sendable {
  var destinationLabel: String
  var url: URL
  var entryCount: Int
}

struct MHLExportSummary: Equatable, Sendable {
  var writtenFiles: [MHLExportFileSummary] = []
  var includedClipCount = 0
  var skippedClipCount = 0

  var message: String {
    let files = writtenFiles.map(\.url.lastPathComponent).joined(separator: ", ")
    return "\(includedClipCount) hashed clips -> \(writtenFiles.count) MHL file(s): \(files)"
  }
}

enum MHLReportError: LocalizedError, Equatable {
  case noEligibleClips
  case canceled
  case forbiddenSourceWrite(String)

  var errorDescription: String? {
    switch self {
    case .noEligibleClips:
      return "No strongly verified clips with SHA256 checksums are available for an MHL report. Run strong verification first."
    case .canceled:
      return "MHL export was canceled."
    case .forbiddenSourceWrite(let path):
      return "Refusing to write MHL onto a source volume path: \(path)"
    }
  }
}

/// Writes classic ASC MHL XML proof-of-transfer artifacts from already-computed
/// strong SHA256 checksums on **copied destinations only**. Never writes to
/// source cards, never invents hashes for fast-verify / failed / pending clips.
final class MHLReportService {
  private let security = SecurityScopedBookmarkManager()

  /// Clips eligible for an honest MHL entry: strong verify success + non-empty checksum.
  static func isEligible(_ clip: Clip) -> Bool {
    guard clip.verificationStatus == .verified else { return false }
    guard let checksum = clip.checksum, !checksum.isEmpty else { return false }
    return true
  }

  func generate(
    project: ClipVaultProject,
    clips: [Clip],
    destinations: [MHLDestination],
    options: MHLExportOptions = MHLExportOptions()
  ) async throws -> MHLExportSummary {
    let eligible = clips.filter(Self.isEligible)
    let skipped = clips.count - eligible.count
    guard !eligible.isEmpty else { throw MHLReportError.noEligibleClips }
    guard !destinations.isEmpty else { throw MHLReportError.noEligibleClips }

    let projectFolder = security.projectFolderURL(for: project)
    let outputRoot = (options.outputDirectory ?? defaultReportsDirectory(for: projectFolder))
      .standardizedFileURL

    try Self.assertSafeOutputDirectory(outputRoot, clips: clips)

    let workID = await BackgroundWorkCoordinator.shared.begin(
      kind: .export,
      label: "MHL \(SafeFilename.safeFolderName(project.name))"
    )

    do {
      var summary = MHLExportSummary(includedClipCount: eligible.count, skippedClipCount: skipped)
      let stamp = Self.timestampFormatter.string(from: options.now)
      let safeProject = SafeFilename.safeFolderName(project.name)

      try await security.withAccessAsync(to: outputRoot) {
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        for destination in destinations {
          if Task.isCancelled { throw MHLReportError.canceled }

          let xml = Self.buildClassicMHLXML(
            projectName: project.name,
            destinationLabel: destination.label,
            clips: eligible,
            destinationRoot: destination.rootURL,
            createdAt: options.now,
            hostname: options.hostname,
            appVersion: options.appVersion
          )

          let safeLabel = SafeFilename.safeFolderName(destination.label)
            .replacingOccurrences(of: " ", with: "_")
          let filename = "\(safeProject)_\(safeLabel)_\(stamp).mhl"
          let target = SafeFilename.uniqueURL(for: outputRoot.appendingPathComponent(filename))

          try Self.assertSafeOutputDirectory(
            target.deletingLastPathComponent(),
            clips: clips
          )
          try xml.write(to: target, atomically: true, encoding: .utf8)
          summary.writtenFiles.append(
            MHLExportFileSummary(
              destinationLabel: destination.label,
              url: target,
              entryCount: eligible.count
            )
          )
        }
      }

      await BackgroundWorkCoordinator.shared.finish(workID)

      if summary.writtenFiles.isEmpty {
        throw MHLReportError.noEligibleClips
      }
      return summary
    } catch {
      await BackgroundWorkCoordinator.shared.finish(workID)
      throw error
    }
  }

  func defaultReportsDirectory(for projectFolder: URL) -> URL {
    projectFolder
      .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
      .appendingPathComponent("reports", isDirectory: true)
  }

  /// Classic ASC MHL 1.x XML (single file, one `<hash>` entry per eligible clip).
  static func buildClassicMHLXML(
    projectName: String,
    destinationLabel: String,
    clips: [Clip],
    destinationRoot: URL,
    createdAt: Date,
    hostname: String,
    appVersion: String
  ) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    var lines: [String] = []
    lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    lines.append("<hashlist version=\"1.1\">")
    lines.append("  <creatorinfo>")
    lines.append("    <name>\(xmlEscape(AppBrand.appName))</name>")
    lines.append("    <version>\(xmlEscape(appVersion))</version>")
    lines.append("    <creationdate>\(iso.string(from: createdAt))</creationdate>")
    lines.append("    <hostname>\(xmlEscape(hostname))</hostname>")
    lines.append("    <tool>\(xmlEscape(AppBrand.appName)) MHL export</tool>")
    lines.append("    <project>\(xmlEscape(projectName))</project>")
    lines.append("    <destination>\(xmlEscape(destinationLabel))</destination>")
    lines.append("  </creatorinfo>")

    for clip in clips where isEligible(clip) {
      let relative = relativePath(for: clip, destinationRoot: destinationRoot)
      let checksum = clip.checksum ?? ""
      lines.append("  <hash>")
      lines.append("    <file>\(xmlEscape(relative))</file>")
      lines.append("    <size>\(clip.fileSize)</size>")
      if let modified = clip.modifiedAt {
        lines.append("    <lastmodificationdate>\(iso.string(from: modified))</lastmodificationdate>")
      }
      lines.append("    <hash>\(xmlEscape(checksum.lowercased()))</hash>")
      lines.append("    <hashformat>sha256</hashformat>")
      lines.append("  </hash>")
    }

    lines.append("</hashlist>")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  static func relativePath(for clip: Clip, destinationRoot: URL) -> String {
    let preferred = clip.destinationRelativePath.isEmpty ? clip.relativePath : clip.destinationRelativePath
    if !preferred.isEmpty { return preferred.replacingOccurrences(of: "\\", with: "/") }

    let rootPath = destinationRoot.standardizedFileURL.path
    let clipPath = URL(fileURLWithPath: clip.currentPath).standardizedFileURL.path
    if clipPath.hasPrefix(rootPath + "/") {
      return String(clipPath.dropFirst(rootPath.count + 1))
    }
    return clip.currentFilename
  }

  /// Hard safety: never write MHL under a clip's source path or its `/Volumes/...` card root.
  static func assertSafeOutputDirectory(_ directory: URL, clips: [Clip]) throws {
    let out = directory.standardizedFileURL.path
    for clip in clips {
      for raw in [clip.originalSourcePath, clip.sourcePath] where !raw.isEmpty {
        let sourceFile = URL(fileURLWithPath: raw).standardizedFileURL
        let sourceParent = sourceFile.deletingLastPathComponent().path
        if out == sourceParent || out.hasPrefix(sourceParent + "/") {
          throw MHLReportError.forbiddenSourceWrite(out)
        }
        let parts = sourceFile.pathComponents
        if parts.count >= 3, parts[1] == "Volumes" {
          let volumeRoot = "/" + parts[1] + "/" + parts[2]
          if out == volumeRoot || out.hasPrefix(volumeRoot + "/") {
            throw MHLReportError.forbiddenSourceWrite(out)
          }
        }
      }
    }
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter
  }()

  private static func xmlEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
