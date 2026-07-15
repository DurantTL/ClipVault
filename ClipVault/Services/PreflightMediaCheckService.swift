import Foundation

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
  private let security = SecurityScopedBookmarkManager()

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
    // Destination/backup roots may live on sandboxed external or NAS volumes,
    // so enumerate them inside a security scope.
    security.withAccess(to: location.rootURL) {
      scanWithinScope(location)
    }
  }

  private func scanWithinScope(_ location: PreflightScanLocation) -> [PreflightCandidate] {
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
