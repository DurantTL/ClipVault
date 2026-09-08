import Foundation

/// Library thumbnail generation collaborator. Thumbnails are always produced
/// from copied project media — never from source cards.
@MainActor
final class LibraryThumbnailCoordinator {
  private let thumbnails = ThumbnailService()
  private let security: SecurityScopedBookmarkManager
  nonisolated(unsafe) private var thumbnailGenerationTask: Task<Void, Never>?
  private var queuedThumbnailIDs: Set<UUID> = []
  private var forcedThumbnailIDs: Set<UUID> = []

  init(security: SecurityScopedBookmarkManager) {
    self.security = security
  }

  /// `nonisolated` so `LibraryViewModel.deinit` (always nonisolated, even for
  /// a @MainActor-owning class) can cancel in-flight work synchronously.
  /// Safe because by the time deinit runs, no other reference to this
  /// coordinator remains to race with the task-handle mutation.
  nonisolated func cancel() {
    thumbnailGenerationTask?.cancel()
    thumbnailGenerationTask = nil
  }

  func thumbnailURL(for clip: Clip, in project: ClipVaultProject) -> URL {
    security.projectFolderURL(for: project)
      .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
      .appendingPathComponent("thumbnails", isDirectory: true)
      .appendingPathComponent(clip.id.uuidString)
      .appendingPathExtension("jpg")
  }

  func existingThumbnailURL(for clip: Clip, in project: ClipVaultProject) -> URL? {
    if let path = clip.thumbnailPath, !path.isEmpty {
      let url = path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : security.projectFolderURL(for: project).appendingPathComponent(path)
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    let cacheURL = thumbnailURL(for: clip, in: project)
    return FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
  }

  func relativePath(for url: URL, project: ClipVaultProject) -> String {
    let projectFolder = security.projectFolderURL(for: project)
    let prefix = projectFolder.path + "/"
    if url.path.hasPrefix(prefix) {
      return String(url.path.dropFirst(prefix.count))
    }
    return url.path
  }

  func normalizeExistingThumbnailPaths(project: inout ClipVaultProject) {
    for index in project.clips.indices {
      if let url = existingThumbnailURL(for: project.clips[index], in: project) {
        project.clips[index].thumbnailPath = relativePath(for: url, project: project)
        if project.clips[index].thumbnailStatus == .pending {
          project.clips[index].thumbnailStatus = .generated
        }
      }
    }
  }

  func enqueue(
    ids: [UUID],
    force: Bool,
    project: ClipVaultProject,
    resolvedMediaURL: (Clip) -> URL?
  ) {
    let newIDs = ids.filter { id in
      guard let clip = project.clips.first(where: { $0.id == id }) else { return false }
      guard clip.copyStatus != .pending, clip.copyStatus != .copying else { return false }
      guard resolvedMediaURL(clip) != nil else { return false }
      return force || existingThumbnailURL(for: clip, in: project) == nil
    }
    guard !newIDs.isEmpty else { return }
    queuedThumbnailIDs.formUnion(newIDs)
    if force {
      forcedThumbnailIDs.formUnion(newIDs)
    }
  }

  func startProcessingIfNeeded(
    project: @escaping () -> ClipVaultProject,
    resolvedMediaURL: @escaping (Clip) -> URL?,
    filteredClipIDs: @escaping () -> [UUID],
    selectedClipID: @escaping () -> UUID?,
    mutate: @escaping (UUID, (inout Clip) -> Void) -> Void,
    save: @escaping () -> Void
  ) {
    guard thumbnailGenerationTask == nil, !queuedThumbnailIDs.isEmpty else { return }
    thumbnailGenerationTask = Task { [weak self] in
      await self?.processQueue(
        project: project,
        resolvedMediaURL: resolvedMediaURL,
        filteredClipIDs: filteredClipIDs,
        selectedClipID: selectedClipID,
        mutate: mutate,
        save: save
      )
    }
  }

  private func processQueue(
    project: () -> ClipVaultProject,
    resolvedMediaURL: (Clip) -> URL?,
    filteredClipIDs: () -> [UUID],
    selectedClipID: () -> UUID?,
    mutate: (UUID, (inout Clip) -> Void) -> Void,
    save: () -> Void
  ) async {
    defer { thumbnailGenerationTask = nil }
    while let id = prioritizedThumbnailID(selectedClipID: selectedClipID(), filteredClipIDs: filteredClipIDs()) {
      queuedThumbnailIDs.remove(id)
      let force = forcedThumbnailIDs.remove(id) != nil
      let current = project()
      guard let clip = current.clips.first(where: { $0.id == id }) else { continue }
      guard let mediaURL = resolvedMediaURL(clip) else { continue }

      let cacheURL = thumbnailURL(for: clip, in: current)
      mutate(id) { clip in
        clip.thumbnailStatus = .generating
        clip.thumbnailErrorMessage = nil
      }
      save()

      do {
        if !force, FileManager.default.fileExists(atPath: cacheURL.path) {
          let relative = relativePath(for: cacheURL, project: current)
          mutate(id) { clip in
            clip.thumbnailPath = relative
            clip.thumbnailStatus = .generated
          }
          save()
          continue
        }

        let quality = ThumbnailQuality(rawValue: UserDefaults.standard.string(forKey: "thumbnailQuality") ?? "balanced") ?? .balanced
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .libraryThumbnail, label: clip.currentFilename)
        defer { Task { await BackgroundWorkCoordinator.shared.finish(workID) } }
        let result = try await thumbnails.generate(
          for: clip,
          mediaURL: mediaURL,
          project: current,
          quality: quality,
          force: force
        )
        mutate(id) { clip in
          clip.thumbnailPath = result.relativePath
          clip.thumbnailStatus = .generated
          clip.thumbnailErrorMessage = nil
        }
        save()
      } catch {
        mutate(id) { clip in
          if FileManager.default.fileExists(atPath: cacheURL.path) {
            clip.thumbnailPath = relativePath(for: cacheURL, project: current)
            clip.thumbnailStatus = .generated
          } else {
            clip.thumbnailStatus = .failed
          }
          clip.thumbnailErrorMessage = error.localizedDescription
        }
        save()
      }
    }
  }

  private func prioritizedThumbnailID(selectedClipID: UUID?, filteredClipIDs: [UUID]) -> UUID? {
    if let selected = selectedClipID, queuedThumbnailIDs.contains(selected) { return selected }
    if let visible = filteredClipIDs.first(where: { queuedThumbnailIDs.contains($0) }) { return visible }
    return queuedThumbnailIDs.first
  }
}
