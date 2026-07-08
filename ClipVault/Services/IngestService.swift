import Foundation

final class IngestService {
    let verifier = VerificationService(); let metadata = MetadataService(); let thumbnails = ThumbnailService(); let store = ProjectStore(); var cancelled = false
    func cancel() { cancelled = true }
    func ingest(name: String, source: URL, destination: URL, videos: [SourceVideo], bookmarks: (Data?,Data?), settings: AppSettings, progress: @escaping @MainActor (IngestProgress) -> Void) async throws -> ClipVaultProject {
        cancelled = false
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
            do { try FileManager.default.copyItem(at: v.url, to: destURL); clip.verificationStatus = .copied; try verifier.verify(source: v.url, destination: destURL, mode: settings.verificationMode); clip.verificationStatus = .verified } catch { clip.verificationStatus = .failed; clip.errorMessage = error.localizedDescription }
            await metadata.enrich(&clip)
            if clip.verificationStatus == .verified, let thumb = try? await thumbnails.generate(for: clip, projectFolder: projectFolder, quality: settings.thumbnailQuality) { clip.thumbnailPath = thumb }
            project.clips.append(clip); done += v.size; try store.save(project)
        }
        await progress(IngestProgress(currentFilename: "", currentIndex: videos.count, totalCount: videos.count, copiedBytes: total, totalBytes: total, message: "Complete"))
        try store.save(project); return project
    }
}
