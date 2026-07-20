import Foundation
import os

final class IngestService {
  let verifier = VerificationService()
  let metadata = MetadataService()
  let thumbnails = ThumbnailService()
  let store = ProjectStore()
  let security = SecurityScopedBookmarkManager()
  // Written from the main actor (UI) and read from the detached copy task,
  // so both flags must live behind a lock.
  private let controlState = OSAllocatedUnfairLock(initialState: (cancelled: false, paused: false))
  private let copyService = StreamingCopyService()
  var isCancelledNow: Bool { controlState.withLock { $0.cancelled } }
  var isPausedNow: Bool { controlState.withLock { $0.paused } }
  func cancel() { controlState.withLock { $0.cancelled = true } }
  func pause() { controlState.withLock { $0.paused = true } }
  func resume() { controlState.withLock { $0.paused = false } }
  private func resetControlState() { controlState.withLock { $0 = (cancelled: false, paused: false) } }
  func ingest(
    name: String, shootName: String, source: URL, destination: URL, videos: [SourceVideo], bookmarks: (Data?, Data?),
    settings: AppSettings, cameraCardMetadata: IngestCameraCardMetadata, progress: @escaping @MainActor (IngestProgress) -> Void
  ) async throws -> ClipVaultProject {
    self.resetControlState()
    self.copyService.isCancelled = { [weak self] in self?.isCancelledNow ?? false }
    self.copyService.isPaused = { [weak self] in self?.isPausedNow ?? false }
    return try await self.security.withAccessAsync(to: source) {
      try await self.security.withAccessAsync(to: destination) {
        let projectFolder = SafeFilename.uniqueURL(
          for: destination.appendingPathComponent(name, isDirectory: true))
        try FileManager.default.createDirectory(
          at: projectFolder, withIntermediateDirectories: true)
        let bm = try? SecurityScopedBookmarkManager().bookmark(for: projectFolder)
        var reservedDestinationPaths = Set<String>()
        var selectedClips: [Clip] = []
        selectedClips.reserveCapacity(videos.count)
        for (idx, video) in videos.enumerated() {
          selectedClips.append(
            self.placeholderClip(
              for: video,
              source: source,
              projectFolder: projectFolder,
              projectName: name,
              shootName: shootName,
              sequence: idx + 1,
              rename: settings.renameFilesDuringIngest,
              preserveSourceStructure: settings.preserveSourceStructure,
              cameraCardMetadata: cameraCardMetadata,
              reservedDestinationPaths: &reservedDestinationPaths
            )
          )
        }
        var project = ClipVaultProject(
          name: name,
          sourceBookmarkData: bookmarks.0,
          destinationBookmarkData: bookmarks.1,
          projectFolderBookmarkData: bm,
          projectFolderPath: projectFolder.path,
          ingestIncomplete: true,
          ingestStatus: .inProgress,
          totalSelectedClips: videos.count,
          copiedClipCount: 0,
          verifiedClipCount: 0,
          failedClipCount: 0,
          pendingClipCount: videos.count,
          lastIngestDate: Date(),
          canResumeIngest: true,
          clips: selectedClips
        )
        project.ingestCameraCardMetadata = cameraCardMetadata.isEmpty ? nil : cameraCardMetadata
        try self.store.save(project)
        let total = videos.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        let started = Date()
        for (idx, v) in videos.enumerated() {
          if self.isCancelledNow {
            project.ingestIncomplete = true
            project.ingestStatus = .canceled
            project.canResumeIngest = true
            self.refreshCounts(&project)
            try self.store.save(project)
            return project
          }
          await progress(
            IngestProgress(
              currentFilename: v.url.lastPathComponent, currentIndex: idx + 1,
              totalCount: videos.count, copiedBytes: done, totalBytes: total,
              bytesPerSecond: Double(done) / max(1, Date().timeIntervalSince(started)),
              message: self.isPausedNow ? "Paused" : "Copying"))
          var clip = project.clips[idx]
          let destURL = URL(fileURLWithPath: clip.currentPath)
          clip.copyStatus = .copying
          project.clips[idx] = clip
          self.refreshCounts(&project)
          try self.store.save(project)
          try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
          do {
            let resumedFromPartial = StreamingCopyService.hasPartial(for: destURL)
            _ = try await self.copyService.copy(
              from: v.url, to: destURL, alreadyCopiedBytes: done, totalBytes: total
            ) { copied in
              progress(
                IngestProgress(
                  currentFilename: v.url.lastPathComponent, currentIndex: idx + 1,
                  totalCount: videos.count, copiedBytes: copied, totalBytes: total,
                  bytesPerSecond: Double(copied) / max(1, Date().timeIntervalSince(started)),
                  message: self.isPausedNow ? "Paused" : "Copying"))
            }
            clip.copyStatus = .copied
            clip.verificationStatus = .copied
            let verificationMode: VerificationMode = resumedFromPartial ? .strong : settings.verificationMode
            try await self.verifier.verify(
              source: v.url, destination: destURL, mode: verificationMode)
            clip.verificationStatus = .verified
            do {
              try await self.copyBackupsIfNeeded(
                primaryFile: destURL,
                projectFolder: projectFolder,
                relativePath: clip.relativePath,
                settings: settings,
                progress: progress
              )
            } catch is CancellationError {
              throw CancellationError()
            } catch {
              clip.errorMessage = "Primary verified. Backup warning: \(error.localizedDescription)"
            }
          } catch is CancellationError {
            clip.verificationStatus = .pending
            clip.errorMessage = "Ingest canceled safely. Resume to continue this copy."
            clip.copyStatus = .pending
            project.clips[idx] = clip
            project.ingestIncomplete = true
            project.ingestStatus = .canceled
            project.canResumeIngest = true
            self.refreshCounts(&project)
            try self.store.save(project)
            return project
          } catch {
            clip.copyStatus = .failed
            clip.verificationStatus = .failed
            clip.errorMessage = StorageRecovery.message(for: error, operation: .ingest)
          }
          if clip.verificationStatus == .verified {
            await self.metadata.enrich(&clip)
            if settings.generateThumbnailsDuringIngest {
              clip.thumbnailStatus = .generating
              do {
                let result = try await self.thumbnails.generate(
                  for: clip,
                  mediaURL: destURL,
                  project: project,
                  quality: settings.thumbnailQuality
                )
                clip.thumbnailPath = result.relativePath
                clip.thumbnailStatus = .generated
                clip.thumbnailErrorMessage = nil
              } catch {
                clip.thumbnailStatus = .failed
                clip.thumbnailErrorMessage = error.localizedDescription
              }
            }
          }
          project.clips[idx] = clip
          done += v.size
          self.refreshCounts(&project)
          try self.store.save(project)
        }
        self.refreshCounts(&project)
        project.ingestStatus = project.failedClipCount > 0 ? .incomplete : .complete
        project.ingestIncomplete = project.ingestStatus != .complete
        project.canResumeIngest = project.ingestStatus.canResume
        try self.store.save(project)
        await progress(
          IngestProgress(
            currentFilename: "", currentIndex: videos.count, totalCount: videos.count,
            copiedBytes: total, totalBytes: total,
            message: project.ingestStatus == .complete ? "Complete" : "Completed with issues"))
        return project
      }
    }
  }

  /// Continues an incomplete project using the same streamed-copy and verification
  /// guarantees as a new ingest. Existing completed destination files are verified
  /// before their project records are marked verified.
  func resume(
    project: ClipVaultProject,
    settings: AppSettings,
    progress: @escaping @MainActor (IngestProgress) -> Void
  ) async throws -> ClipVaultProject {
    guard let sourceBookmark = project.sourceBookmarkData else {
      throw NSError(
        domain: "ClipVault",
        code: 21,
        userInfo: [NSLocalizedDescriptionKey: "Source access is unavailable. Reconnect the source card and open it with New Ingest before resuming."]
      )
    }

    self.resetControlState()
    self.copyService.isCancelled = { [weak self] in self?.isCancelledNow ?? false }
    self.copyService.isPaused = { [weak self] in self?.isPausedNow ?? false }

    let sourceRoot = try security.resolve(sourceBookmark)
    let projectFolder = security.projectFolderURL(for: project)
    return try await security.withAccessAsync(to: sourceRoot) {
      try await self.security.withAccessAsync(to: projectFolder) {
        var resumed = project
        resumed.ingestStatus = .inProgress
        resumed.canResumeIngest = true
        try self.store.save(resumed)

        let unfinished = resumed.clips.indices.filter {
          resumed.clips[$0].verificationStatus != .verified
        }
        let totalBytes = unfinished.reduce(Int64(0)) {
          $0 + resumed.clips[$1].expectedFileSize
        }
        var completedBytes: Int64 = 0

        for (position, index) in unfinished.enumerated() {
          if self.isCancelledNow { break }
          var clip = resumed.clips[index]
          let source: URL
          if !clip.sourceRelativePath.isEmpty {
            source = sourceRoot.appendingPathComponent(clip.sourceRelativePath)
          } else {
            source = URL(fileURLWithPath: clip.sourcePath.isEmpty ? clip.originalSourcePath : clip.sourcePath)
          }
          let destination = URL(fileURLWithPath: clip.currentPath)
          guard FileManager.default.fileExists(atPath: source.path) else {
            clip.copyStatus = .failed
            clip.verificationStatus = .failed
            clip.errorMessage = "Source is not connected. Reconnect the source card and try again."
            resumed.clips[index] = clip
            self.refreshCounts(&resumed)
            try self.store.save(resumed)
            continue
          }

          do {
            try FileManager.default.createDirectory(
              at: destination.deletingLastPathComponent(),
              withIntermediateDirectories: true
            )
            clip.copyStatus = .copying
            clip.verificationStatus = .pending
            resumed.clips[index] = clip
            try self.store.save(resumed)

            if !FileManager.default.fileExists(atPath: destination.path) {
              _ = try await self.copyService.copy(
                from: source,
                to: destination,
                alreadyCopiedBytes: completedBytes,
                totalBytes: totalBytes
              ) { copied in
                progress(IngestProgress(
                  currentFilename: clip.currentFilename,
                  currentIndex: position + 1,
                  totalCount: unfinished.count,
                  copiedBytes: copied,
                  totalBytes: totalBytes,
                  message: "Resuming copy"
                ))
              }
            }
            try await self.verifier.verify(source: source, destination: destination, mode: .strong)
            clip.copyStatus = .copied
            clip.verificationStatus = .verified
            clip.errorMessage = nil
          } catch is CancellationError {
            clip.copyStatus = .pending
            clip.verificationStatus = .pending
            clip.errorMessage = "Ingest canceled safely. Resume to continue this copy."
            resumed.ingestStatus = .canceled
            resumed.ingestIncomplete = true
            resumed.canResumeIngest = true
          } catch {
            clip.copyStatus = .failed
            clip.verificationStatus = .failed
            clip.errorMessage = StorageRecovery.message(for: error, operation: .resumeIngest)
          }
          resumed.clips[index] = clip
          completedBytes += clip.expectedFileSize
          self.refreshCounts(&resumed)
          try self.store.save(resumed)
          if resumed.ingestStatus == .canceled { break }
        }

        let wasCanceled = resumed.ingestStatus == .canceled || self.isCancelledNow
        self.refreshCounts(&resumed)
        if wasCanceled {
          resumed.ingestStatus = .canceled
          resumed.ingestIncomplete = true
          resumed.canResumeIngest = true
        } else {
          resumed.ingestStatus = resumed.pendingClipCount == 0 && resumed.failedClipCount == 0
            ? .complete
            : .incomplete
          resumed.ingestIncomplete = resumed.ingestStatus != .complete
          resumed.canResumeIngest = resumed.ingestStatus.canResume
        }
        try self.store.save(resumed)
        return resumed
      }
    }
  }

  private func placeholderClip(
    for video: SourceVideo,
    source: URL,
    projectFolder: URL,
    projectName: String,
    shootName: String,
    sequence: Int,
    rename: Bool,
    preserveSourceStructure: Bool,
    cameraCardMetadata: IngestCameraCardMetadata,
    reservedDestinationPaths: inout Set<String>
  ) -> Clip {
    let outputFilename = outputFilename(for: video, projectName: projectName, sequence: sequence, rename: rename)
    let cleanShootName = SafeFilename.safeFolderName(shootName)
    let flatRelativePath = cleanShootName.isEmpty ? outputFilename : "\(cleanShootName)/\(outputFilename)"
    let rel = preserveSourceStructure && !rename ? video.relativePath : flatRelativePath
    let destURL = SafeFilename.uniqueURL(
      for: projectFolder.appendingPathComponent(rel),
      reserving: &reservedDestinationPaths
    )
    var clip = Clip(
      originalSourcePath: video.url.path,
      originalFilename: video.url.lastPathComponent,
      currentPath: destURL.path,
      currentFilename: destURL.lastPathComponent,
      relativePath: destURL.path.replacingOccurrences(of: projectFolder.path + "/", with: ""),
      fileSize: video.size,
      createdAt: video.createdAt,
      modifiedAt: video.modifiedAt,
      ingestDate: nil,
      sonyCardFolderPath: video.sonyCardFolderPath,
      cardVolumeName: source.lastPathComponent
    )
    clip.sourcePath = video.url.path
    clip.sourceRelativePath = video.relativePath
    clip.expectedFileSize = video.size
    clip.destinationRelativePath = clip.relativePath
    clip.copyStatus = .pending
    clip.verificationStatus = .pending
    clip.cameraLabel = cameraCardMetadata.cameraLabel
    clip.camera = cameraCardMetadata.cameraNameModel
    clip.cameraOperator = cameraCardMetadata.operatorName
    clip.cardVolumeName = cameraCardMetadata.cardOrReelName.isEmpty ? clip.cardVolumeName : cameraCardMetadata.cardOrReelName
    clip.shootDay = cameraCardMetadata.shootDay
    return clip
  }

  private func refreshCounts(_ project: inout ClipVaultProject) {
    // Buckets are mutually exclusive and exhaustive so copied + failed + pending
    // always equals the clip count shown in progress UI.
    func isFailed(_ clip: Clip) -> Bool {
      clip.copyStatus == .failed || clip.verificationStatus == .failed
    }
    func isCopied(_ clip: Clip) -> Bool {
      !isFailed(clip) && (clip.copyStatus == .copied || clip.verificationStatus == .verified)
    }
    project.totalSelectedClips = max(project.totalSelectedClips, project.clips.count)
    project.copiedClipCount = project.clips.filter(isCopied).count
    project.verifiedClipCount = project.clips.filter { $0.verificationStatus == .verified }.count
    project.failedClipCount = project.clips.filter(isFailed).count
    project.pendingClipCount = project.clips.filter { !isFailed($0) && !isCopied($0) }.count
    project.lastIngestDate = Date()
  }

  private func outputFilename(for video: SourceVideo, projectName: String, sequence: Int, rename: Bool) -> String {
    guard rename else { return video.url.lastPathComponent }
    let date = video.createdAt ?? video.modifiedAt ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let safeProject = SafeFilename.safeFolderName(projectName)
    return "\(safeProject)-\(formatter.string(from: date))-\(String(format: "%04d", sequence)).\(video.url.pathExtension)"
  }

  private func copyBackupsIfNeeded(
    primaryFile: URL,
    projectFolder: URL,
    relativePath: String,
    settings: AppSettings,
    progress: @escaping @MainActor (IngestProgress) -> Void
  ) async throws {
    typealias BackupConfiguration = (path: String, bookmark: String, persistKey: String)
    let backups: [BackupConfiguration]
    switch settings.backupTransferMode {
    case "Primary + Backup 1":
      backups = [(
        settings.backupDestination1Path,
        settings.backupDestination1BookmarkBase64,
        StoragePreferences.backup1BookmarkKey
      )]
    case "Primary + Backup 1 + Backup 2":
      backups = [
        (
          settings.backupDestination1Path,
          settings.backupDestination1BookmarkBase64,
          StoragePreferences.backup1BookmarkKey
        ),
        (
          settings.backupDestination2Path,
          settings.backupDestination2BookmarkBase64,
          StoragePreferences.backup2BookmarkKey
        ),
      ]
    default:
      backups = []
    }

    var warnings: [String] = []
    for (index, backup) in backups.enumerated() {
      let label = "Backup \(index + 1)"
      guard !backup.path.isEmpty else {
        warnings.append("\(label) is not configured.")
        continue
      }
      guard let root = StoragePreferences.backupURL(
        path: backup.path,
        bookmarkBase64: backup.bookmark,
        persistKey: backup.persistKey
      ), FileManager.default.fileExists(atPath: root.path) else {
        warnings.append("\(label) is unavailable. The primary copy remains verified.")
        continue
      }

      do {
        let destination = SafeFilename.uniqueURL(
          for: root
            .appendingPathComponent(projectFolder.lastPathComponent, isDirectory: true)
            .appendingPathComponent(relativePath)
        )
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        let size = Int64((try? primaryFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        await progress(IngestProgress(
          currentFilename: primaryFile.lastPathComponent,
          copiedBytes: 0,
          totalBytes: size,
          message: "Copying \(label)"
        ))
        let resumedFromPartial = StreamingCopyService.hasPartial(for: destination)
        _ = try await self.copyService.copy(
          from: primaryFile,
          to: destination,
          alreadyCopiedBytes: 0,
          totalBytes: size
        ) { copied in
          progress(IngestProgress(
            currentFilename: primaryFile.lastPathComponent,
            copiedBytes: copied,
            totalBytes: size,
            message: "Copying \(label)"
          ))
        }
        await progress(IngestProgress(
          currentFilename: primaryFile.lastPathComponent,
          copiedBytes: size,
          totalBytes: size,
          message: "Verifying \(label)"
        ))
        let verificationMode: VerificationMode = resumedFromPartial ? .strong : settings.verificationMode
        try await self.verifier.verify(
          source: primaryFile,
          destination: destination,
          mode: verificationMode
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        warnings.append(StorageRecovery.message(for: error, operation: .backup))
      }
    }

    if !warnings.isEmpty {
      throw BackupTransferWarnings(messages: warnings)
    }
  }
}

private struct BackupTransferWarnings: LocalizedError {
  let messages: [String]
  var errorDescription: String? { messages.joined(separator: " ") }
}
