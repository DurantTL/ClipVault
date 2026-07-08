import Foundation

final class IngestService {
    let verifier = VerificationService(); let metadata = MetadataService(); let thumbnails = ThumbnailService(); let store = ProjectStore(); let security = SecurityScopedBookmarkManager(); var cancelled = false
    private let copyService = StreamingCopyService()
    func cancel() { cancelled = true }
    func ingest(name: String, source: URL, destination: URL, videos: [SourceVideo], bookmarks: (Data?,Data?), settings: AppSettings, progress: @escaping @MainActor (IngestProgress) -> Void) async throws -> ClipVaultProject {
        cancelled = false; copyService.isCancelled = { [weak self] in self?.cancelled ?? false }
        return try await security.withAccessAsync(to: source) {
            try await security.withAccessAsync(to: destination) {
                let projectFolder = SafeFilename.uniqueURL(for: destination.appendingPathComponent(name, isDirectory: true)); try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
                let bm = try? SecurityScopedBookmarkManager().bookmark(for: projectFolder)
                var project = ClipVaultProject(name: name, sourceBookmarkData: bookmarks.0, destinationBookmarkData: bookmarks.1, projectFolderBookmarkData: bm, projectFolderPath: projectFolder.path)
                let total = videos.reduce(Int64(0)) { $0 + $1.size }; var done: Int64 = 0; let started = Date()
                for (idx, v) in videos.enumerated() {
                    if cancelled { project.ingestIncomplete = true; try store.save(project); return project }
                    await progress(IngestProgress(currentFilename: v.url.lastPathComponent, currentIndex: idx+1, totalCount: videos.count, copiedBytes: done, totalBytes: total, bytesPerSecond: Double(done)/max(1, Date().timeIntervalSince(started)), message: "Copying"))
                    let rel = settings.preserveSourceStructure ? v.relativePath : v.url.lastPathComponent
                    let destURL = SafeFilename.uniqueURL(for: projectFolder.appendingPathComponent(rel)); try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    var clip = Clip(originalSourcePath: v.url.path, originalFilename: v.url.lastPathComponent, currentPath: destURL.path, currentFilename: destURL.lastPathComponent, relativePath: destURL.path.replacingOccurrences(of: projectFolder.path + "/", with: ""), fileSize: v.size, createdAt: v.createdAt)
                    do {
                        _ = try await copyService.copy(from: v.url, to: destURL, alreadyCopiedBytes: done, totalBytes: total) { copied in
                            progress(IngestProgress(currentFilename: v.url.lastPathComponent, currentIndex: idx+1, totalCount: videos.count, copiedBytes: copied, totalBytes: total, bytesPerSecond: Double(copied)/max(1, Date().timeIntervalSince(started)), message: "Copying"))
                        }
                        clip.verificationStatus = .copied
                        try await verifier.verify(source: v.url, destination: destURL, mode: settings.verificationMode)
                        clip.verificationStatus = .verified
                    } catch is CancellationError {
                        clip.verificationStatus = .failed; clip.errorMessage = "Ingest canceled during copy."; project.clips.append(clip); project.ingestIncomplete = true; try store.save(project); return project
                    } catch {
                        clip.verificationStatus = .failed; clip.errorMessage = error.localizedDescription
                    }
                    if clip.verificationStatus == .verified {
                        await metadata.enrich(&clip)
                        if let thumb = try? await thumbnails.generate(for: clip, projectFolder: projectFolder, quality: settings.thumbnailQuality) { clip.thumbnailPath = thumb }
                    }
                    project.clips.append(clip); done += v.size; try store.save(project)
                }
                await progress(IngestProgress(currentFilename: "", currentIndex: videos.count, totalCount: videos.count, copiedBytes: total, totalBytes: total, message: "Complete"))
                try store.save(project); return project
            }
        }
    }
}
