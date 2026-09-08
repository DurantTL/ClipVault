import AppKit
import Foundation

@MainActor final class NewIngestViewModel: ObservableObject {
  static let rememberedSourceBookmarksKey = "rememberedSourceBookmarks"
  static let rememberedManualSourcePathsKey = "rememberedManualSourcePaths"
  @Published var sourceURL: URL?
  @Published var destinationURL: URL? {
    didSet { updateWindowCleanupDestination() }
  }
  @Published var projectName = "" {
    didSet { updateWindowCleanupDestination() }
  }
  @Published var shootName = "" {
    didSet { updateWindowCleanupDestination() }
  }
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
  @Published var cameraCardMetadata = IngestCameraCardMetadata()
  /// When true, Selection stays locked to preflight `.newMedia` clips and is
  /// re-applied whenever Preflight results refresh (Select New Only mode).
  @Published var prefersNewOnlySelection = false

  let scanner = SourceScanner()
  let volumeSourceService = VolumeSourceService()
  let bookmarks = SecurityScopedBookmarkManager()
  let ingestService = IngestService()
  let ingestPreviewThumbnails = IngestPreviewThumbnailService()
  let windowPreviewCleanup = IngestWindowPreviewCleanup()
  var queuedPreviewThumbnailIDs = Set<UUID>()
  var pendingPreviewThumbnailClips: [ScannedVideo] = []
  var activePreviewThumbnailCount = 0
  var maxConcurrentPreviewThumbnails = SystemPerformanceProfile.current().recommendedThumbnailConcurrency
  var previewThumbnailTasks: [UUID: Task<Void, Never>] = [:]
  var sourceBookmarkDataByID: [String: Data] = [:]
  var grantedSourceURLsByID: [String: URL] = [:]
  var activeAccessURLsByPath: [String: URL] = [:]
  private var scanGeneration = 0

  var cameraLabelSuggestions: [String] {
    Array(Set(IngestCameraCardMetadata.defaults + Self.loadCameraLabelHistory() + [cameraCardMetadata.cameraLabel]))
      .filter { !$0.isEmpty }
      .sorted()
  }

  struct SourceAccessGrant {
    var url: URL
    var needsBookmarkRefresh: Bool
  }

  init() {
    sourceBookmarkDataByID = Self.loadRememberedSourceBookmarks()
    recentManualSources = Self.loadRememberedManualSourcePaths().map { path in
      let url = URL(fileURLWithPath: path)
      var option = VolumeSourceService().manualSource(for: url)
      option.bookmarkData = sourceBookmarkDataByID[option.id]
      return option
    }
    ingestPreviewThumbnails.cleanCache(destinationRoot: nil)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    projectName = "\(formatter.string(from: Date())) Video Ingest"
    updateWindowCleanupDestination()
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

  private func updateWindowCleanupDestination() {
    windowPreviewCleanup.update(destinationRoot: finalOutputURL)
  }

  func chooseDestination() {
    guard let url = pickFolder(canCreateDirectories: true) else { return }
    destinationURL = url
    retainAccess(to: url)
    error = nil
    updateFreeSpace()
    queueInitialPreviewThumbnails()
  }

  func chooseBackup1(settings: AppSettings) {
    guard let url = pickFolder(canCreateDirectories: true) else { return }
    settings.backupDestination1Path = url.path
    // Never overwrite a stored bookmark with a failed creation.
    if let bookmark = (try? bookmarks.bookmark(for: url))?.base64EncodedString() {
      settings.backupDestination1BookmarkBase64 = bookmark
    }
  }

  func chooseBackup2(settings: AppSettings) {
    guard let url = pickFolder(canCreateDirectories: true) else { return }
    settings.backupDestination2Path = url.path
    if let bookmark = (try? bookmarks.bookmark(for: url))?.base64EncodedString() {
      settings.backupDestination2BookmarkBase64 = bookmark
    }
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
    scanGeneration += 1
    let generation = scanGeneration
    detectSonyCard()
    cancelPreviewThumbnailWork()
    maxConcurrentPreviewThumbnails = settings.performanceTuning().ingestPreviewThumbnailConcurrency
    ingestPreviewThumbnails.cleanCache(destinationRoot: finalOutputURL)
    queuedPreviewThumbnailIDs.removeAll()
    pendingPreviewThumbnailClips.removeAll()
    activePreviewThumbnailCount = 0
    isScanning = true
    error = nil
    videos = []
    sessions = []
    // Rescan rebuilds sessions; drop stale new-only selection until Preflight refreshes.
    // Keep prefersNewOnlySelection so a subsequent Preflight run re-applies New-only.

    let includeProxyFiles = settings.includeProxyFiles
    Task { [weak self] in
      let scanStart = Date()
      do {
        let scannedVideos = try await Task.detached(priority: .userInitiated) {
          try SourceScanner().scan(source: sourceURL, includeProxyFiles: includeProxyFiles)
        }.value
        guard let self, self.scanGeneration == generation, self.sourceURL == sourceURL else { return }
        self.videos = scannedVideos
        PerformanceLogger.shared.scan(duration: Date().timeIntervalSince(scanStart), fileCount: scannedVideos.count)
        self.sessions = self.buildSessions(from: scannedVideos, source: sourceURL)
        self.updateFreeSpace()
        self.queueInitialPreviewThumbnails()
      } catch {
        guard let self, self.scanGeneration == generation, self.sourceURL == sourceURL else { return }
        self.error = error.localizedDescription
      }
      guard let self, self.scanGeneration == generation, self.sourceURL == sourceURL else { return }
      self.isScanning = false
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
    error = nil
    guard hasSufficientDestinationCapacity else {
      error = destinationCapacityMessage
        ?? "The destination does not have enough free space for the selected clips."
      return nil
    }
    isIngesting = true
    canceledSummary = nil
    defer { isIngesting = false }
    do {
      let project = try await ingestService.ingest(
        name: projectName,
        shootName: shootName,
        source: source,
        destination: destination,
        videos: selectedVideos,
        bookmarks: (try? bookmarks.bookmark(for: source), try? bookmarks.bookmark(for: destination)),
        settings: settings,
        cameraCardMetadata: cameraCardMetadata
      ) { self.progress = $0 }
      Self.rememberCameraLabel(cameraCardMetadata.cameraLabel)
      if project.ingestStatus == .complete,
        settings.sourcePreviewCleanupPolicy == .afterSuccessfulIngest {
        ingestPreviewThumbnails.cleanCache(destinationRoot: finalOutputURL)
      }
      if project.ingestStatus == .canceled {
        canceledSummary = "Ingest canceled safely. Open the partial project to resume it."
      }
      return project
    } catch is CancellationError {
      canceledSummary = "Ingest canceled. \(progress.currentIndex) of \(progress.totalCount) files copied."
      return nil
    } catch {
      self.error = StorageRecovery.message(for: error, operation: .ingest)
      return nil
    }
  }

  private static let cameraLabelHistoryKey = "cameraLabelHistory"

  private static func loadCameraLabelHistory() -> [String] {
    UserDefaults.standard.stringArray(forKey: cameraLabelHistoryKey) ?? []
  }

  private static func rememberCameraLabel(_ label: String) {
    let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    let values = ([clean] + loadCameraLabelHistory().filter { $0.caseInsensitiveCompare(clean) != .orderedSame })
    UserDefaults.standard.set(Array(values.prefix(12)), forKey: Self.cameraLabelHistoryKey)
  }

  var selectedSessions: [IngestSession] { sessions.filter(\.selected) }

  var selectedVideos: [SourceVideo] {
    let selectedIDs = Set(sessions.flatMap { $0.selectedClips.map(\.id) })
    return videos.filter { selectedIDs.contains($0.id) }
  }

  var selectedTotalSize: Int64 { sessions.reduce(0) { $0 + $1.selectedSize } }
  var selectedClipCount: Int { sessions.reduce(0) { $0 + $1.selectedClipCount } }

  var destinationCapacityStatus: VolumeCapacity.PreflightStatus {
    VolumeCapacity.preflightStatus(
      requiredBytes: selectedTotalSize,
      availableBytes: destinationFreeSpace
    )
  }

  var hasSufficientDestinationCapacity: Bool {
    destinationCapacityStatus != .insufficient
  }

  var destinationCapacityMessage: String? {
    guard destinationURL != nil, selectedTotalSize > 0 else { return nil }
    switch destinationCapacityStatus {
    case .unknown:
      return "Free space could not be confirmed for this destination. Keep the drive or network share connected during ingest."
    case .sufficient:
      return nil
    case .lowAfterIngest:
      guard let destinationFreeSpace else { return nil }
      let remaining = max(0, destinationFreeSpace - selectedTotalSize)
      return "Low space warning: about \(FileSizeFormatterUtil.string(remaining)) will remain after this ingest."
    case .insufficient:
      guard let destinationFreeSpace else { return nil }
      let additional = max(0, selectedTotalSize - destinationFreeSpace)
      return "Not enough destination space. Free at least \(FileSizeFormatterUtil.string(additional)) more, choose another destination, or select fewer clips."
    }
  }

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

  deinit {
    for task in previewThumbnailTasks.values { task.cancel() }
    windowPreviewCleanup.cleanIfNeeded()
    for url in activeAccessURLsByPath.values { url.stopAccessingSecurityScopedResource() }
  }
}
