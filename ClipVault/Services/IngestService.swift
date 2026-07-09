import Foundation

final class IngestService {
  let verifier = VerificationService()
  let metadata = MetadataService()
  let thumbnails = ThumbnailService()
  let store = ProjectStore()
  let security = SecurityScopedBookmarkManager()
  var cancelled = false
  var paused = false
  private let copyService = StreamingCopyService()
  func cancel() { cancelled = true }
  func pause() { paused = true }
  func resume() { paused = false }
  func ingest(
    name: String, shootName: String, source: URL, destination: URL, videos: [SourceVideo], bookmarks: (Data?, Data?),
    settings: AppSettings, progress: @escaping @MainActor (IngestProgress) -> Void
  ) async throws -> ClipVaultProject {
    self.cancelled = false
    self.copyService.isCancelled = { [weak self] in self?.cancelled ?? false }
    self.copyService.isPaused = { [weak self] in self?.paused ?? false }
    return try await self.security.withAccessAsync(to: source) {
      try await self.security.withAccessAsync(to: destination) {
        let projectFolder = SafeFilename.uniqueURL(
          for: destination.appendingPathComponent(name, isDirectory: true))
        try FileManager.default.createDirectory(
          at: projectFolder, withIntermediateDirectories: true)
        let bm = try? SecurityScopedBookmarkManager().bookmark(for: projectFolder)
        let selectedClips = videos.enumerated().map { idx, v in
          self.placeholderClip(
            for: v,
            source: source,
            projectFolder: projectFolder,
            projectName: name,
            shootName: shootName,
            sequence: idx + 1,
            rename: settings.renameFilesDuringIngest,
            preserveSourceStructure: settings.preserveSourceStructure
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
        try self.store.save(project)
        let total = videos.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        let started = Date()
        for (idx, v) in videos.enumerated() {
          if self.cancelled {
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
              message: self.paused ? "Paused" : "Copying"))
          var clip = project.clips[idx]
          let destURL = URL(fileURLWithPath: clip.currentPath)
          clip.copyStatus = .copying
          project.clips[idx] = clip
          self.refreshCounts(&project)
          try self.store.save(project)
          try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
          do {
            _ = try await self.copyService.copy(
              from: v.url, to: destURL, alreadyCopiedBytes: done, totalBytes: total
            ) { copied in
              progress(
                IngestProgress(
                  currentFilename: v.url.lastPathComponent, currentIndex: idx + 1,
                  totalCount: videos.count, copiedBytes: copied, totalBytes: total,
                  bytesPerSecond: Double(copied) / max(1, Date().timeIntervalSince(started)),
                  message: self.paused ? "Paused" : "Copying"))
            }
            clip.copyStatus = .copied
            clip.verificationStatus = .copied
            try await self.verifier.verify(
              source: v.url, destination: destURL, mode: settings.verificationMode)
            clip.verificationStatus = .verified
            do {
              try await self.copyBackupsIfNeeded(
                primaryFile: destURL,
                projectFolder: projectFolder,
                relativePath: clip.relativePath,
                settings: settings,
                progress: progress
              )
            } catch {
              clip.errorMessage = "Primary verified. Backup warning: \(error.localizedDescription)"
            }
          } catch is CancellationError {
            clip.verificationStatus = .failed
            clip.errorMessage = "Ingest canceled during copy."
            clip.copyStatus = .failed
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
            clip.errorMessage = error.localizedDescription
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
        await progress(
          IngestProgress(
            currentFilename: "", currentIndex: videos.count, totalCount: videos.count,
            copiedBytes: total, totalBytes: total, message: "Complete"))
        project.ingestIncomplete = false
        project.ingestStatus = project.failedClipCount > 0 ? .incomplete : .complete
        project.canResumeIngest = project.ingestStatus.canResume
        self.refreshCounts(&project)
        try self.store.save(project)
        return project
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
    preserveSourceStructure: Bool
  ) -> Clip {
    let outputFilename = outputFilename(for: video, projectName: projectName, sequence: sequence, rename: rename)
    let cleanShootName = SafeFilename.safeFolderName(shootName)
    let flatRelativePath = cleanShootName.isEmpty ? outputFilename : "\(cleanShootName)/\(outputFilename)"
    let rel = preserveSourceStructure && !rename ? video.relativePath : flatRelativePath
    let destURL = SafeFilename.uniqueURL(for: projectFolder.appendingPathComponent(rel))
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
    return clip
  }

  private func refreshCounts(_ project: inout ClipVaultProject) {
    project.totalSelectedClips = max(project.totalSelectedClips, project.clips.count)
    project.copiedClipCount = project.clips.filter { $0.copyStatus == .copied || $0.verificationStatus == .verified }.count
    project.verifiedClipCount = project.clips.filter { $0.verificationStatus == .verified }.count
    project.failedClipCount = project.clips.filter { $0.copyStatus == .failed || $0.verificationStatus == .failed }.count
    project.pendingClipCount = project.clips.filter { $0.copyStatus == .pending || $0.copyStatus == .copying }.count
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
    let backupPaths: [String]
    switch settings.backupTransferMode {
    case "Primary + Backup 1":
      backupPaths = [settings.backupDestination1Path]
    case "Primary + Backup 1 + Backup 2":
      backupPaths = [settings.backupDestination1Path, settings.backupDestination2Path]
    default:
      backupPaths = []
    }

    for (index, path) in backupPaths.enumerated() where !path.isEmpty {
      let root = URL(fileURLWithPath: path, isDirectory: true)
      guard FileManager.default.fileExists(atPath: root.path) else {
        await progress(IngestProgress(message: "Backup \(index + 1) unavailable; primary remains verified"))
        continue
      }
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
      await progress(IngestProgress(currentFilename: primaryFile.lastPathComponent, copiedBytes: 0, totalBytes: size, message: "Copying Backup \(index + 1)"))
      _ = try await self.copyService.copy(
        from: primaryFile,
        to: destination,
        alreadyCopiedBytes: 0,
        totalBytes: size
      ) { copied in
        progress(IngestProgress(currentFilename: primaryFile.lastPathComponent, copiedBytes: copied, totalBytes: size, message: "Verifying Backup \(index + 1)"))
      }
      try await self.verifier.verify(source: primaryFile, destination: destination, mode: settings.verificationMode)
    }
  }
}
