import AppKit
import Foundation

extension NewIngestViewModel {

  func queuePreviewThumbnails(for session: IngestSession, limit: Int = 8) {
    for clip in session.clips.prefix(limit) {
      queuePreviewThumbnail(for: clip)
    }
  }

  func queuePreviewThumbnail(for clip: ScannedVideo) {
    guard let sourceURL else { return }
    guard StoragePreferences.sourcePreviewDirectory(destinationRoot: finalOutputURL) != nil else { return }
    guard clip.previewThumbnailStatus == .pending || clip.previewThumbnailStatus == .failed else { return }
    guard !queuedPreviewThumbnailIDs.contains(clip.id) else { return }
    queuedPreviewThumbnailIDs.insert(clip.id)
    pendingPreviewThumbnailClips.append(clip)
    updatePreviewThumbnailState(clipID: clip.id, status: .generating, path: nil, errorMessage: nil, duration: nil)
    startNextPreviewThumbnailIfNeeded()
  }

  private func startNextPreviewThumbnailIfNeeded() {
    guard activePreviewThumbnailCount < maxConcurrentPreviewThumbnails else { return }
    guard let sourceURL else { return }
    guard !pendingPreviewThumbnailClips.isEmpty else { return }

    let clip = pendingPreviewThumbnailClips.removeFirst()
    let destinationRoot = finalOutputURL
    activePreviewThumbnailCount += 1

    // Weak self so an in-flight thumbnail task never keeps the view model (and
    // its retained security-scoped access) alive after the ingest window closes.
    let task = Task(priority: .utility) { [weak self, service = ingestPreviewThumbnails] in
      do {
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .ingestPreviewThumbnail, label: clip.filename)
        defer { Task { await BackgroundWorkCoordinator.shared.finish(workID) } }
        let result = try await service.generate(
          for: clip,
          sourceRoot: sourceURL,
          destinationRoot: destinationRoot
        )
        await MainActor.run { [weak self] in
          self?.finishPreviewThumbnail(
            clipID: clip.id,
            status: .generated,
            path: result.path,
            errorMessage: nil,
            duration: result.duration
          )
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.finishPreviewThumbnail(
            clipID: clip.id,
            status: .failed,
            path: nil,
            errorMessage: error.localizedDescription,
            duration: nil
          )
        }
      }
    }
    previewThumbnailTasks[clip.id] = task
  }

  func cancelPreviewThumbnailWork() {
    for task in previewThumbnailTasks.values { task.cancel() }
    previewThumbnailTasks.removeAll()
    pendingPreviewThumbnailClips.removeAll()
    queuedPreviewThumbnailIDs.removeAll()
    activePreviewThumbnailCount = 0
  }

  private func finishPreviewThumbnail(
    clipID: UUID,
    status: ThumbnailStatus,
    path: String?,
    errorMessage: String?,
    duration: Double?
  ) {
    previewThumbnailTasks[clipID] = nil
    activePreviewThumbnailCount = max(0, activePreviewThumbnailCount - 1)
    updatePreviewThumbnailState(
      clipID: clipID,
      status: status,
      path: path,
      errorMessage: errorMessage,
      duration: duration
    )
    startNextPreviewThumbnailIfNeeded()
  }

  func setClip(_ clip: ScannedVideo, in session: IngestSession, selected: Bool) {
    prefersNewOnlySelection = false
    guard let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }),
      let clipIndex = sessions[sessionIndex].clips.firstIndex(where: { $0.id == clip.id }) else { return }
    sessions[sessionIndex].clips[clipIndex].selected = selected
    sessions[sessionIndex].selected = sessions[sessionIndex].clips.contains { $0.selected }
  }

  func queueInitialPreviewThumbnails() {
    for session in sessions {
      queuePreviewThumbnails(for: session, limit: 8)
    }
  }

  private func updatePreviewThumbnailState(
    clipID: UUID,
    status: ThumbnailStatus,
    path: String?,
    errorMessage: String?,
    duration: Double?
  ) {
    for sessionIndex in sessions.indices {
      guard let clipIndex = sessions[sessionIndex].clips.firstIndex(where: { $0.id == clipID }) else { continue }
      sessions[sessionIndex].clips[clipIndex].previewThumbnailStatus = status
      if let path { sessions[sessionIndex].clips[clipIndex].previewThumbnailPath = path }
      if status == .failed { sessions[sessionIndex].clips[clipIndex].previewThumbnailPath = nil }
      sessions[sessionIndex].clips[clipIndex].previewThumbnailErrorMessage = errorMessage
      if let duration { sessions[sessionIndex].clips[clipIndex].duration = duration }
      return
    }
  }

  func setSession(at index: Int, selected: Bool) {
    sessions[index].selected = selected
    for clipIndex in sessions[index].clips.indices {
      sessions[index].clips[clipIndex].selected = selected
    }
  }

  func buildSessions(from videos: [SourceVideo], source: URL) -> [IngestSession] {
    let sorted = videos.sorted { bestShotTime(for: $0) < bestShotTime(for: $1) }
    let groups: [[SourceVideo]]
    switch groupingMode {
    case .allFiles:
      groups = sorted.isEmpty ? [] : [sorted]
    case .sourceFolder:
      groups = Dictionary(grouping: sorted) { URL(fileURLWithPath: $0.relativePath).deletingLastPathComponent().path }
        .values.map { $0.sorted { bestShotTime(for: $0) < bestShotTime(for: $1) } }
        .sorted { bestShotTime(for: $0.first!) < bestShotTime(for: $1.first!) }
    case .date, .dateAndGap:
      var built: [[SourceVideo]] = []
      for video in sorted {
        let date = bestShotTime(for: video)
        if let lastGroup = built.last, let previous = lastGroup.last {
          let previousDate = bestShotTime(for: previous)
          let withinGap = groupingMode == .date || date.timeIntervalSince(previousDate) <= Double(timeGap.rawValue * 60)
          if Calendar.current.isDate(date, inSameDayAs: previousDate) && withinGap {
            built[built.count - 1].append(video)
          } else {
            built.append([video])
          }
        } else {
          built.append([video])
        }
      }
      groups = built
    }
    return groups.map { group in
      let dates = group.map { bestShotTime(for: $0) }.sorted()
      let scanned = group.map { video in
        ScannedVideo(id: video.id, url: video.url, filename: video.url.lastPathComponent, fileSize: video.size, createdAt: video.createdAt, modifiedAt: video.modifiedAt, duration: nil, cameraType: video.cardType, sourceRelativePath: video.relativePath)
      }
      let start = dates.first ?? Date()
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .short
      return IngestSession(title: formatter.string(from: start), date: start, startTime: start, endTime: dates.last ?? start, clips: scanned, totalSize: group.reduce(0) { $0 + $1.size }, cameraType: group.first?.cardType ?? detectedCardType.rawValue, sourceVolumeName: source.lastPathComponent)
    }
  }

  private func bestShotTime(for video: SourceVideo) -> Date {
    video.createdAt ?? video.modifiedAt ?? filenameDate(video.url.lastPathComponent) ?? .distantPast
  }

  private func filenameDate(_ filename: String) -> Date? {
    let digits = filename.filter(\.isNumber)
    guard digits.count >= 14 else { return nil }
    let prefix = String(digits.prefix(14))
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.date(from: prefix)
  }

  func updateFreeSpace() {
    guard let destinationURL else { return }
    destinationFreeSpace = VolumeCapacity.availableCapacity(for: destinationURL)
  }
}
