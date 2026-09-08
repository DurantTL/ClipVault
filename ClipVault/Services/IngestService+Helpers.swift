extension IngestService {
  func placeholderClip(
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

  func refreshCounts(_ project: inout ClipVaultProject) {
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

  func outputFilename(for video: SourceVideo, projectName: String, sequence: Int, rename: Bool) -> String {
    guard rename else { return video.url.lastPathComponent }
    let date = video.createdAt ?? video.modifiedAt ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let safeProject = SafeFilename.safeFolderName(projectName)
    return "\(safeProject)-\(formatter.string(from: date))-\(String(format: "%04d", sequence)).\(video.url.pathExtension)"
  }

  func copyBackupsIfNeeded(
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
        _ = try await self.verifier.verify(
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
