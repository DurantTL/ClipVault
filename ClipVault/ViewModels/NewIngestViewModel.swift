import AppKit
import Foundation

@MainActor final class NewIngestViewModel: ObservableObject {
  @Published var sourceURL: URL?
  @Published var destinationURL: URL?
  @Published var projectName = ""
  @Published var shootName = ""
  @Published var videos: [SourceVideo] = []
  @Published var sessions: [IngestSession] = []
  @Published var progress = IngestProgress()
  @Published var error: String?
  @Published var isIngesting = false
  @Published var canceledSummary: String?
  @Published var detectedCardType: DetectedCardType = .generic
  @Published var destinationFreeSpace: Int64?
  @Published var groupingMode: IngestGroupingMode = .dateAndGap
  @Published var timeGap: IngestTimeGap = .ninety
  @Published var alreadyImportedMode: AlreadyImportedMode = .skipAlreadyCopied
  @Published var selectDate = Date()

  let scanner = SourceScanner()
  let bookmarks = SecurityScopedBookmarkManager()
  let ingestService = IngestService()
  private let ingestPreviewThumbnails = IngestPreviewThumbnailService()
  private var queuedPreviewThumbnailIDs = Set<UUID>()
  private var pendingPreviewThumbnailClips: [ScannedVideo] = []
  private var activePreviewThumbnailCount = 0
  private let maxConcurrentPreviewThumbnails = 2

  init() {
    ingestPreviewThumbnails.cleanCache()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    projectName = "\(formatter.string(from: Date())) Video Ingest"
  }

  var finalOutputURL: URL? {
    guard let destinationURL else { return nil }
    var url = destinationURL.appendingPathComponent(projectName, isDirectory: true)
    if !shootName.trimmingCharacters(in: .whitespaces).isEmpty {
      url.appendPathComponent(SafeFilename.safeFolderName(shootName), isDirectory: true)
    }
    return url
  }

  func chooseSource(settings: AppSettings) {
    if let url = pickFolder(canCreateDirectories: false) {
      sourceURL = url
      detectSonyCard()
      scan(settings: settings)
    }
  }

  func chooseDestination() {
    destinationURL = pickFolder(canCreateDirectories: true)
    updateFreeSpace()
  }

  func chooseBackup1(settings: AppSettings) {
    settings.backupDestination1Path = pickFolder(canCreateDirectories: true)?.path ?? ""
  }

  func chooseBackup2(settings: AppSettings) {
    settings.backupDestination2Path = pickFolder(canCreateDirectories: true)?.path ?? ""
  }

  func pickFolder(canCreateDirectories: Bool) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = canCreateDirectories
    return panel.runModal() == .OK ? panel.url : nil
  }

  func detectSonyCard() {
    guard let sourceURL else { return }
    detectedCardType = scanner.detectCardType(source: sourceURL)
  }

  func scan(settings: AppSettings) {
    guard let sourceURL else { return }
    do {
      detectSonyCard()
      ingestPreviewThumbnails.cleanCache()
      queuedPreviewThumbnailIDs.removeAll()
      pendingPreviewThumbnailClips.removeAll()
      activePreviewThumbnailCount = 0
      videos = try scanner.scan(source: sourceURL, includeProxyFiles: settings.includeProxyFiles)
      sessions = buildSessions(from: videos, source: sourceURL)
      updateFreeSpace()
      queueInitialPreviewThumbnails()
    } catch { self.error = error.localizedDescription }
  }

  func createProjectFolder() {
    guard let url = finalOutputURL else { return }
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func revealDestination() {
    guard let url = finalOutputURL ?? destinationURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func start(settings: AppSettings) async -> ClipVaultProject? {
    guard let source = sourceURL, let destination = destinationURL else { return nil }
    isIngesting = true
    canceledSummary = nil
    defer { isIngesting = false }
    do {
      return try await ingestService.ingest(
        name: projectName,
        shootName: shootName,
        source: source,
        destination: destination,
        videos: selectedVideos,
        bookmarks: (try? bookmarks.bookmark(for: source), try? bookmarks.bookmark(for: destination)),
        settings: settings
      ) { self.progress = $0 }
    } catch is CancellationError {
      canceledSummary = "Ingest canceled. \(progress.currentIndex) of \(progress.totalCount) files copied."
      return nil
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  var selectedSessions: [IngestSession] { sessions.filter(\.selected) }

  var selectedVideos: [SourceVideo] {
    let selectedIDs = Set(sessions.flatMap { $0.selectedClips.map(\.id) })
    return videos.filter { selectedIDs.contains($0.id) }
  }

  var selectedTotalSize: Int64 { sessions.reduce(0) { $0 + $1.selectedSize } }
  var selectedClipCount: Int { sessions.reduce(0) { $0 + $1.selectedClipCount } }

  var statusMessage: String {
    if let error { return error }
    if let canceledSummary { return canceledSummary }
    if sourceURL == nil { return "No source selected" }
    if destinationURL == nil { return "Destination not selected" }
    if sessions.isEmpty { return "No sessions scanned" }
    if selectedVideos.isEmpty { return "Nothing selected" }
    return "Ready to ingest"
  }

  func selectAllSessions() {
    for index in sessions.indices { setSession(at: index, selected: true) }
  }

  func clearSessionSelection() {
    for index in sessions.indices { setSession(at: index, selected: false) }
  }

  func selectTodaySessions() {
    for index in sessions.indices { setSession(at: index, selected: Calendar.current.isDateInToday(sessions[index].date)) }
  }

  func selectSessions(on date: Date) {
    for index in sessions.indices { setSession(at: index, selected: Calendar.current.isDate(sessions[index].date, inSameDayAs: date)) }
  }

  func selectNewOnlySessions() { selectAllSessions() }

  func setSession(_ session: IngestSession, selected: Bool) {
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    setSession(at: index, selected: selected)
  }

  func toggleSession(_ session: IngestSession) {
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    setSession(at: index, selected: !sessions[index].selected)
  }

  func queuePreviewThumbnails(for session: IngestSession, limit: Int = 8) {
    for clip in session.clips.prefix(limit) {
      queuePreviewThumbnail(for: clip)
    }
  }

  func queuePreviewThumbnail(for clip: ScannedVideo) {
    guard let sourceURL else { return }
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
    activePreviewThumbnailCount += 1

    Task {
      do {
        let result = try await ingestPreviewThumbnails.generate(for: clip, sourceRoot: sourceURL)
        await MainActor.run {
          self.finishPreviewThumbnail(
            clipID: clip.id,
            status: .generated,
            path: result.path,
            errorMessage: nil,
            duration: result.duration
          )
        }
      } catch {
        await MainActor.run {
          self.finishPreviewThumbnail(
            clipID: clip.id,
            status: .failed,
            path: nil,
            errorMessage: error.localizedDescription,
            duration: nil
          )
        }
      }
    }
  }

  private func finishPreviewThumbnail(
    clipID: UUID,
    status: ThumbnailStatus,
    path: String?,
    errorMessage: String?,
    duration: Double?
  ) {
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
    guard let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }),
      let clipIndex = sessions[sessionIndex].clips.firstIndex(where: { $0.id == clip.id }) else { return }
    sessions[sessionIndex].clips[clipIndex].selected = selected
    sessions[sessionIndex].selected = sessions[sessionIndex].clips.contains { $0.selected }
  }

  private func queueInitialPreviewThumbnails() {
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

  private func setSession(at index: Int, selected: Bool) {
    sessions[index].selected = selected
    for clipIndex in sessions[index].clips.indices {
      sessions[index].clips[clipIndex].selected = selected
    }
  }

  private func buildSessions(from videos: [SourceVideo], source: URL) -> [IngestSession] {
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

  private func updateFreeSpace() {
    guard let destinationURL else { return }
    destinationFreeSpace = try? destinationURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }
}
