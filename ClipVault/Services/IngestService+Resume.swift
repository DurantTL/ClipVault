import Foundation

extension IngestService {
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
            let outcome = try await self.verifier.verify(source: source, destination: destination, mode: .strong)
            clip.copyStatus = .copied
            clip.verificationStatus = .verified
            if let checksum = outcome.checksum, !checksum.isEmpty {
              clip.checksum = checksum
            }
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
}
