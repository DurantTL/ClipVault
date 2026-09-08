import Foundation
import SwiftUI

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

    // Re-apply New-only when the operator asked for it, or when ingest is set to
    // skip already-copied media (auto new-only after every Preflight refresh).
    let shouldApplyNewOnly =
      ingest.prefersNewOnlySelection || ingest.alreadyImportedMode == .skipAlreadyCopied
    if shouldApplyNewOnly {
      applyNewOnlySelection(to: ingest)
    }

    let currentSummary = PreflightSummary(results: results)
    message = "Preflight complete: \(currentSummary.newCount) new, \(currentSummary.alreadyImportedCount) already imported, \(currentSummary.reviewCount) need review."
  }

  /// Select only clips whose preflight status is New (`.newMedia`).
  ///
  /// Intentional exceptions / non-selections (still visible in the UI):
  /// - Already at Destination / Already in Project / Already on Backup → excluded
  /// - Possible Duplicate → visible, not treated as New
  /// - Same Name Different Size → visible, not treated as New
  /// - Missing result after a check → not treated as New
  /// - No results yet → clears selection (never silently Select All)
  func applyNewOnlySelection(to ingest: NewIngestViewModel) {
    ingest.applyNewOnlySelection(from: results)
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
