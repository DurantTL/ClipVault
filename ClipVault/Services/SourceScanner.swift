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

// MARK: - Preflight Media Check

enum PreflightClipStatus: String, CaseIterable, Codable, Sendable {
  case newMedia
  case alreadyInDestination
  case alreadyInAnotherProject
  case alreadyOnBackup
  case possibleDuplicate
  case sameNameDifferentSize

  var label: String {
    switch self {
    case .newMedia: return "New"
    case .alreadyInDestination: return "Already at Destination"
    case .alreadyInAnotherProject: return "Already in Project"
    case .alreadyOnBackup: return "Already on Backup"
    case .possibleDuplicate: return "Possible Duplicate"
    case .sameNameDifferentSize: return "Same Name, Different Size"
    }
  }

  var isNew: Bool { self == .newMedia }
  var shouldSelectByDefault: Bool { self == .newMedia }

  var needsReview: Bool {
    self == .possibleDuplicate || self == .sameNameDifferentSize
  }
}

enum PreflightCandidateKind: String, Codable, Sendable {
  case destination
  case project
  case backup
}

struct PreflightSourceFile: Identifiable, Equatable, Sendable {
  let id: UUID
  let filename: String
  let fileSize: Int64
  let modifiedAt: Date?
  let duration: Double?
}

struct PreflightCandidate: Equatable, Sendable {
  let filename: String
  let fileSize: Int64
  let modifiedAt: Date?
  let duration: Double?
  let path: String
  let kind: PreflightCandidateKind
  let locationLabel: String
}

struct PreflightScanLocation: Sendable {
  let rootURL: URL
  let kind: PreflightCandidateKind
  let label: String
}

struct PreflightClipResult: Identifiable, Equatable, Sendable {
  var id: UUID { sourceID }
  let sourceID: UUID
  let status: PreflightClipStatus
  let matchedPath: String?
  let matchedLocationLabel: String?
  let reason: String
}

struct PreflightSummary: Equatable, Sendable {
  var total = 0
  var newCount = 0
  var alreadyImportedCount = 0
  var reviewCount = 0

  init(results: [UUID: PreflightClipResult]) {
    total = results.count
    for result in results.values {
      switch result.status {
      case .newMedia:
        newCount += 1
      case .alreadyInDestination, .alreadyInAnotherProject, .alreadyOnBackup:
        alreadyImportedCount += 1
      case .possibleDuplicate, .sameNameDifferentSize:
        reviewCount += 1
      }
    }
  }
}

actor PreflightMediaCheckService {
  private let dateTolerance: TimeInterval = 2
  private let durationTolerance: TimeInterval = 0.5

  func check(
    sourceFiles: [PreflightSourceFile],
    knownCandidates: [PreflightCandidate],
    scanLocations: [PreflightScanLocation]
  ) -> [UUID: PreflightClipResult] {
    var candidates = knownCandidates
    for location in scanLocations {
      candidates.append(contentsOf: scan(location))
    }

    let byName = Dictionary(grouping: candidates) {
      normalizedFilename($0.filename)
    }
    let bySize = Dictionary(grouping: candidates) { $0.fileSize }

    var results: [UUID: PreflightClipResult] = [:]
    results.reserveCapacity(sourceFiles.count)

    for source in sourceFiles {
      let sameName = byName[normalizedFilename(source.filename)] ?? []
      let sameNameAndSize = sameName.filter { $0.fileSize == source.fileSize }

      if let exact = preferredCandidate(
        from: sameNameAndSize.filter { datesMatch(source.modifiedAt, $0.modifiedAt) }
      ) {
        results[source.id] = exactResult(sourceID: source.id, candidate: exact)
        continue
      }

      if let sameNameSameSize = preferredCandidate(from: sameNameAndSize) {
        results[source.id] = PreflightClipResult(
          sourceID: source.id,
          status: .possibleDuplicate,
          matchedPath: sameNameSameSize.path,
          matchedLocationLabel: sameNameSameSize.locationLabel,
          reason: "Filename and file size match, but the modified date does not. Review before copying."
        )
        continue
      }

      if let differentSize = preferredCandidate(
        from: sameName.filter { $0.fileSize != source.fileSize }
      ) {
        results[source.id] = PreflightClipResult(
          sourceID: source.id,
          status: .sameNameDifferentSize,
          matchedPath: differentSize.path,
          matchedLocationLabel: differentSize.locationLabel,
          reason: "A file with the same name exists, but its size is different."
        )
        continue
      }

      let sameSize = bySize[source.fileSize] ?? []
      if let possible = preferredCandidate(
        from: sameSize.filter { candidate in
          guard let sourceDuration = source.duration,
            let candidateDuration = candidate.duration else {
            return datesMatch(source.modifiedAt, candidate.modifiedAt)
          }
          return abs(sourceDuration - candidateDuration) <= durationTolerance
        }
      ) {
        results[source.id] = PreflightClipResult(
          sourceID: source.id,
          status: .possibleDuplicate,
          matchedPath: possible.path,
          matchedLocationLabel: possible.locationLabel,
          reason: "File size and recording details match a differently named file."
        )
        continue
      }

      results[source.id] = PreflightClipResult(
        sourceID: source.id,
        status: .newMedia,
        matchedPath: nil,
        matchedLocationLabel: nil,
        reason: "No matching media was found in the checked locations."
      )
    }

    return results
  }

  private func scan(_ location: PreflightScanLocation) -> [PreflightCandidate] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: location.rootURL.path),
      let enumerator = fileManager.enumerator(
        at: location.rootURL,
        includingPropertiesForKeys: [
          .isRegularFileKey,
          .fileSizeKey,
          .contentModificationDateKey,
          .isHiddenKey
        ],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
      ) else {
      return []
    }

    var candidates: [PreflightCandidate] = []
    for case let url as URL in enumerator {
      if Task.isCancelled { break }
      let path = url.standardizedFileURL.path
      if path.contains("/.clipvault-cache/")
        || url.lastPathComponent.contains(".clipvault-partial")
        || url.lastPathComponent == ".clipvault-project.json" {
        continue
      }

      guard SourceScanner.supported.contains(url.pathExtension.lowercased()) else { continue }
      guard let values = try? url.resourceValues(forKeys: [
        .isRegularFileKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .isHiddenKey
      ]), values.isRegularFile == true, values.isHidden != true else {
        continue
      }

      candidates.append(
        PreflightCandidate(
          filename: url.lastPathComponent,
          fileSize: Int64(values.fileSize ?? 0),
          modifiedAt: values.contentModificationDate,
          duration: nil,
          path: path,
          kind: location.kind,
          locationLabel: location.label
        )
      )
    }
    return candidates
  }

  private func exactResult(
    sourceID: UUID,
    candidate: PreflightCandidate
  ) -> PreflightClipResult {
    let status: PreflightClipStatus
    switch candidate.kind {
    case .destination:
      status = .alreadyInDestination
    case .project:
      status = .alreadyInAnotherProject
    case .backup:
      status = .alreadyOnBackup
    }

    return PreflightClipResult(
      sourceID: sourceID,
      status: status,
      matchedPath: candidate.path,
      matchedLocationLabel: candidate.locationLabel,
      reason: "Filename, file size, and modified date match."
    )
  }

  private func preferredCandidate(
    from candidates: [PreflightCandidate]
  ) -> PreflightCandidate? {
    candidates.min { lhs, rhs in
      let lhsRank = priority(lhs.kind)
      let rhsRank = priority(rhs.kind)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }
  }

  private func priority(_ kind: PreflightCandidateKind) -> Int {
    switch kind {
    case .destination: return 0
    case .project: return 1
    case .backup: return 2
    }
  }

  private func normalizedFilename(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
    guard let lhs, let rhs else { return false }
    return abs(lhs.timeIntervalSince(rhs)) <= dateTolerance
  }
}

@MainActor final class PreflightMediaCheckViewModel: ObservableObject {
  @Published var results: [UUID: PreflightClipResult] = [:]
  @Published var isRunning = false
  @Published var message = "Run Preflight to check the destination, recent projects, and configured backups."
  @Published var lastCheckedAt: Date?

  let service = PreflightMediaCheckService()

  var hasResults: Bool { !results.isEmpty }
  var summary: PreflightSummary { PreflightSummary(results: results) }

  func result(for clipID: UUID) -> PreflightClipResult? {
    results[clipID]
  }

  func reset() {
    results = [:]
    lastCheckedAt = nil
    message = "Run Preflight to check the destination, recent projects, and configured backups."
  }

  func run(
    ingest: NewIngestViewModel,
    settings: AppSettings
  ) async {
    guard !isRunning else { return }
    guard !ingest.videos.isEmpty else {
      message = "Scan a source before running Preflight."
      return
    }
    guard let destination = ingest.destinationURL else {
      message = "Choose a destination before running Preflight."
      return
    }

    isRunning = true
    message = "Checking media locations…"
    defer { isRunning = false }

    let durationByID = Dictionary(uniqueKeysWithValues:
      ingest.sessions.flatMap { session in
        session.clips.compactMap { clip in
          clip.duration.map { (clip.id, $0) }
        }
      }
    )

    let sourceFiles = ingest.videos.map { video in
      PreflightSourceFile(
        id: video.id,
        filename: video.url.lastPathComponent,
        fileSize: video.size,
        modifiedAt: video.modifiedAt,
        duration: durationByID[video.id]
      )
    }

    let recentProjects = (try? ProjectStore().loadAll()) ?? []
    let knownCandidates = projectCandidates(from: recentProjects)
    let scanLocations = preflightLocations(destination: destination, settings: settings)

    results = await service.check(
      sourceFiles: sourceFiles,
      knownCandidates: knownCandidates,
      scanLocations: scanLocations
    )
    lastCheckedAt = Date()

    if ingest.alreadyImportedMode == .skipAlreadyCopied {
      applyNewOnlySelection(to: ingest)
    }

    let currentSummary = PreflightSummary(results: results)
    message = "Preflight complete: \(currentSummary.newCount) new, \(currentSummary.alreadyImportedCount) already imported, \(currentSummary.reviewCount) need review."
  }

  func applyNewOnlySelection(to ingest: NewIngestViewModel) {
    guard !results.isEmpty else {
      ingest.selectAllSessions()
      return
    }

    for sessionIndex in ingest.sessions.indices {
      for clipIndex in ingest.sessions[sessionIndex].clips.indices {
        let clipID = ingest.sessions[sessionIndex].clips[clipIndex].id
        ingest.sessions[sessionIndex].clips[clipIndex].selected =
          results[clipID]?.status.shouldSelectByDefault ?? true
      }
      ingest.sessions[sessionIndex].selected =
        ingest.sessions[sessionIndex].clips.contains(where: { $0.selected })
    }
  }

  private func preflightLocations(
    destination: URL,
    settings: AppSettings
  ) -> [PreflightScanLocation] {
    var locations = [
      PreflightScanLocation(
        rootURL: destination,
        kind: .destination,
        label: destination.lastPathComponent.isEmpty
          ? destination.path
          : destination.lastPathComponent
      )
    ]

    if settings.backupTransferMode != "Primary only",
      let backup1 = StoragePreferences.backupURL(
        path: settings.backupDestination1Path,
        bookmarkBase64: settings.backupDestination1BookmarkBase64
      ) {
      locations.append(
        PreflightScanLocation(rootURL: backup1, kind: .backup, label: "Backup 1")
      )
    }

    if settings.backupTransferMode == "Primary + Backup 1 + Backup 2",
      let backup2 = StoragePreferences.backupURL(
        path: settings.backupDestination2Path,
        bookmarkBase64: settings.backupDestination2BookmarkBase64
      ) {
      locations.append(
        PreflightScanLocation(rootURL: backup2, kind: .backup, label: "Backup 2")
      )
    }

    return locations
  }

  private func projectCandidates(
    from projects: [ClipVaultProject]
  ) -> [PreflightCandidate] {
    var candidates: [PreflightCandidate] = []

    for project in projects {
      for clip in project.clips {
        guard clip.copyStatus == .copied || clip.verificationStatus == .verified else {
          continue
        }

        let size = clip.expectedFileSize > 0 ? clip.expectedFileSize : clip.fileSize
        let path = clip.currentPath.isEmpty
          ? URL(fileURLWithPath: project.projectFolderPath)
            .appendingPathComponent(clip.relativePath).path
          : clip.currentPath

        candidates.append(
          PreflightCandidate(
            filename: clip.originalFilename,
            fileSize: size,
            modifiedAt: clip.modifiedAt,
            duration: clip.duration,
            path: path,
            kind: .project,
            locationLabel: project.name
          )
        )

        if clip.currentFilename.caseInsensitiveCompare(clip.originalFilename)
          != .orderedSame {
          candidates.append(
            PreflightCandidate(
              filename: clip.currentFilename,
              fileSize: size,
              modifiedAt: clip.modifiedAt,
              duration: clip.duration,
              path: path,
              kind: .project,
              locationLabel: project.name
            )
          )
        }
      }
    }

    return candidates
  }
}
