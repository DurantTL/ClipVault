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
        var project = ClipVaultProject(
          name: name, sourceBookmarkData: bookmarks.0, destinationBookmarkData: bookmarks.1,
          projectFolderBookmarkData: bm, projectFolderPath: projectFolder.path)
        let total = videos.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        let started = Date()
        for (idx, v) in videos.enumerated() {
          if self.cancelled {
            project.ingestIncomplete = true
            try self.store.save(project)
            return project
          }
          await progress(
            IngestProgress(
              currentFilename: v.url.lastPathComponent, currentIndex: idx + 1,
              totalCount: videos.count, copiedBytes: done, totalBytes: total,
              bytesPerSecond: Double(done) / max(1, Date().timeIntervalSince(started)),
              message: self.paused ? "Paused" : "Copying"))
          let cleanShootName = SafeFilename.safeFolderName(shootName)
          let flatRelativePath = cleanShootName.isEmpty ? v.url.lastPathComponent : "\(cleanShootName)/\(v.url.lastPathComponent)"
          let rel = settings.preserveSourceStructure ? v.relativePath : flatRelativePath
          let destURL = SafeFilename.uniqueURL(for: projectFolder.appendingPathComponent(rel))
          try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
          var clip = Clip(
            originalSourcePath: v.url.path, originalFilename: v.url.lastPathComponent,
            currentPath: destURL.path, currentFilename: destURL.lastPathComponent,
            relativePath: destURL.path.replacingOccurrences(of: projectFolder.path + "/", with: ""),
            fileSize: v.size, createdAt: v.createdAt, modifiedAt: v.modifiedAt, ingestDate: Date(), sonyCardFolderPath: v.sonyCardFolderPath, cardVolumeName: source.lastPathComponent)
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
            project.clips.append(clip)
            project.ingestIncomplete = true
            try self.store.save(project)
            return project
          } catch {
            clip.verificationStatus = .failed
            clip.errorMessage = error.localizedDescription
          }
          if clip.verificationStatus == .verified {
            await self.metadata.enrich(&clip)
            if let thumb = try? await self.thumbnails.generate(
              for: clip, projectFolder: projectFolder, quality: settings.thumbnailQuality)
            {
              clip.thumbnailPath = thumb
            }
          }
          project.clips.append(clip)
          done += v.size
          try self.store.save(project)
        }
        await progress(
          IngestProgress(
            currentFilename: "", currentIndex: videos.count, totalCount: videos.count,
            copiedBytes: total, totalBytes: total, message: "Complete"))
        try self.store.save(project)
        return project
      }
    }
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
