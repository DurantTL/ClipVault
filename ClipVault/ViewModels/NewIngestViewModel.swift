import AppKit
import Foundation

@MainActor final class NewIngestViewModel: ObservableObject {
  private static let rememberedSourceBookmarksKey = "rememberedSourceBookmarks"
  @Published var sourceURL: URL?
  @Published var destinationURL: URL?
  @Published var projectName = ""
  @Published var shootName = ""
  @Published var videos: [SourceVideo] = []
  @Published var sessions: [IngestSession] = []
  @Published var progress = IngestProgress()
  @Published var error: String?
  @Published var isIngesting = false
  @Published var isScanning = false
  @Published var canceledSummary: String?
  @Published var detectedCardType: DetectedCardType = .generic
  @Published var destinationFreeSpace: Int64?
  @Published var groupingMode: IngestGroupingMode = .dateAndGap
  @Published var timeGap: IngestTimeGap = .ninety
  @Published var alreadyImportedMode: AlreadyImportedMode = .skipAlreadyCopied
  @Published var selectDate = Date()
  @Published var sourceOptions: [SourceVolumeOption] = []
  @Published var recentManualSources: [SourceVolumeOption] = []
  @Published var selectedSourceID: String?


  let scanner = SourceScanner()
  let volumeSourceService = VolumeSourceService()
  let bookmarks = SecurityScopedBookmarkManager()
  let ingestService = IngestService()
  private let ingestPreviewThumbnails = IngestPreviewThumbnailService()
  private var queuedPreviewThumbnailIDs = Set<UUID>()
  private var pendingPreviewThumbnailClips: [ScannedVideo] = []
  private var activePreviewThumbnailCount = 0
  private var maxConcurrentPreviewThumbnails = SystemPerformanceProfile.current().recommendedThumbnailConcurrency
  private var previewThumbnailTasks: [UUID: Task<Void, Never>] = [:]
  private var sourceBookmarkDataByID: [String: Data] = [:]
  private var accessedSourceURL: URL?

  init() {
    sourceBookmarkDataByID = Self.loadRememberedSourceBookmarks()
    ingestPreviewThumbnails.cleanCache()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    projectName = "\(formatter.string(from: Date())) Video Ingest"
    refreshSources()
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
      var manual = volumeSourceService.manualSource(for: url)
      manual.bookmarkData = try? bookmarks.bookmark(for: url)
      if let bookmarkData = manual.bookmarkData { remember(bookmarkData, for: manual.id) }
      if !recentManualSources.contains(where: { $0.id == manual.id }) {
        recentManualSources.insert(manual, at: 0)
      }
      selectGrantedSource(manual, grantedURL: url, settings: settings)
    }
  }

  func refreshSources() {
    let selectedPath = sourceURL?.standardizedFileURL.path
    sourceOptions = volumeSourceService.scanMountedSources().map { option in
      var refreshed = option
      refreshed.bookmarkData = sourceBookmarkDataByID[option.id]
      return refreshed
    }
    recentManualSources = recentManualSources.map { manual in
      var refreshed = volumeSourceService.manualSource(for: manual.url)
      refreshed.isAvailable = FileManager.default.fileExists(atPath: manual.url.path)
      refreshed.bookmarkData = manual.bookmarkData ?? sourceBookmarkDataByID[manual.id]
      return refreshed
    }
    if let selectedPath, !sourceOptions.contains(where: { $0.id == selectedPath }) && !recentManualSources.contains(where: { $0.id == selectedPath }) {
      var disconnected = volumeSourceService.manualSource(for: URL(fileURLWithPath: selectedPath))
      disconnected.isAvailable = false
      recentManualSources.insert(disconnected, at: 0)
      selectedSourceID = selectedPath
    }
  }

  func selectDetectedSource(_ source: SourceVolumeOption, settings: AppSettings) {
    guard source.isAvailable else {
      error = "That source is disconnected. Reconnect it or use Add Source to choose a folder manually."
      return
    }
    guard let grantedURL = ensureAccessForDetectedSource(source) else {
      error = "Access not granted. Choose the card or folder before ClipVault scans it."
      return
    }
    var grantedSource = volumeSourceService.manualSource(for: grantedURL)
    grantedSource.id = source.id
    grantedSource.name = source.name
    grantedSource.volumeKind = source.volumeKind
    grantedSource.iconName = source.iconName
    grantedSource.bookmarkData = try? bookmarks.bookmark(for: grantedURL)
    if let bookmarkData = grantedSource.bookmarkData { remember(bookmarkData, for: source.id) }
    selectGrantedSource(grantedSource, grantedURL: grantedURL, settings: settings)
  }

  private func selectGrantedSource(_ source: SourceVolumeOption, grantedURL: URL, settings: AppSettings) {
    activateAccess(to: grantedURL)
    sourceURL = grantedURL
    selectedSourceID = source.id
    error = nil
    detectSonyCard()
    scan(settings: settings)
  }

  private func ensureAccessForDetectedSource(_ option: SourceVolumeOption) -> URL? {
    // Camera cards are read-only sources. The removable-media sandbox entitlement
    // permits scanning them directly, so card switching does not require a Finder
    // confirmation for every mounted card.
    if option.volumeKind == .removableCard {
      return option.url
    }

    if let bookmarkData = option.bookmarkData ?? sourceBookmarkDataByID[option.id],
      let resolved = try? bookmarks.resolve(bookmarkData) {
      // Refresh the persisted bookmark after resolution. This handles a mounted
      // card whose path or bookmark representation changed since last use.
      if let refreshed = try? bookmarks.bookmark(for: resolved) {
        remember(refreshed, for: option.id)
      }
      return resolved
    }

    let panel = NSOpenPanel()
    panel.title = "Allow ClipVault to Access This Source"
    panel.message = "Choose this card or folder so ClipVault can scan it."
    panel.prompt = "Allow Access"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    if FileManager.default.fileExists(atPath: option.url.path) {
      panel.directoryURL = option.url
    }

    guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
    let selectedPath = selectedURL.standardizedFileURL.path
    let detectedPath = option.url.standardizedFileURL.path
    guard selectedPath == detectedPath || selectedPath.hasPrefix(detectedPath + "/") else {
      error = "Choose the detected card or one of its folders to allow access."
      return nil
    }
    return selectedURL
  }

  private func remember(_ bookmarkData: Data, for sourceID: String) {
    sourceBookmarkDataByID[sourceID] = bookmarkData
    if let data = try? PropertyListEncoder().encode(sourceBookmarkDataByID) {
      UserDefaults.standard.set(data, forKey: Self.rememberedSourceBookmarksKey)
    }
  }

  private static func loadRememberedSourceBookmarks() -> [String: Data] {
    if let data = UserDefaults.standard.data(forKey: rememberedSourceBookmarksKey),
      let bookmarks = try? PropertyListDecoder().decode([String: Data].self, from: data) {
      return bookmarks
    }
    // Preserve permissions granted by the previous implementation when possible.
    return UserDefaults.standard.dictionary(forKey: rememberedSourceBookmarksKey) as? [String: Data] ?? [:]
  }

  private func activateAccess(to url: URL) {
    if accessedSourceURL?.standardizedFileURL != url.standardizedFileURL {
      accessedSourceURL?.stopAccessingSecurityScopedResource()
      accessedSourceURL = url.startAccessingSecurityScopedResource() ? url : nil
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
    detectSonyCard()
    cancelPreviewThumbnailWork()
    maxConcurrentPreviewThumbnails = settings.performanceTuning().ingestPreviewThumbnailConcurrency
    ingestPreviewThumbnails.cleanCache()
    queuedPreviewThumbnailIDs.removeAll()
    pendingPreviewThumbnailClips.removeAll()
    activePreviewThumbnailCount = 0
    isScanning = true
    error = nil

    let includeProxyFiles = settings.includeProxyFiles
    Task { [weak self] in
      let scanStart = Date()
      do {
        let scannedVideos = try await Task.detached(priority: .userInitiated) {
          try SourceScanner().scan(source: sourceURL, includeProxyFiles: includeProxyFiles)
        }.value
        guard let self, self.sourceURL == sourceURL else { return }
        self.videos = scannedVideos
        PerformanceLogger.shared.scan(duration: Date().timeIntervalSince(scanStart), fileCount: scannedVideos.count)
        self.sessions = self.buildSessions(from: scannedVideos, source: sourceURL)
        self.updateFreeSpace()
        self.queueInitialPreviewThumbnails()
      } catch {
        self?.error = error.localizedDescription
      }
      self?.isScanning = false
    }
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
    if isScanning { return "Scanning source…" }
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

    let task = Task(priority: .utility) {
      do {
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .ingestPreviewThumbnail, label: clip.filename)
        defer { Task { await BackgroundWorkCoordinator.shared.finish(workID) } }
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
    previewThumbnailTasks[clip.id] = task
  }

  func cancelPreviewThumbnailWork() {
    for task in previewThumbnailTasks.values { task.cancel() }
    previewThumbnailTasks.removeAll()
    pendingPreviewThumbnailClips.removeAll()
    queuedPreviewThumbnailIDs.removeAll()
    activePreviewThumbnailCount = 0
  }

  deinit {
    accessedSourceURL?.stopAccessingSecurityScopedResource()
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
