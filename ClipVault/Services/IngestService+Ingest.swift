import Foundation

extension IngestService {
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
            let outcome = try await self.verifier.verify(
              source: v.url, destination: destURL, mode: verificationMode)
            clip.verificationStatus = .verified
            // Persist strong SHA256 only - fast mode never invents a checksum.
            if let checksum = outcome.checksum, !checksum.isEmpty {
              clip.checksum = checksum
            }
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
}
