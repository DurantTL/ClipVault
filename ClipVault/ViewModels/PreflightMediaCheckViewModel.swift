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
