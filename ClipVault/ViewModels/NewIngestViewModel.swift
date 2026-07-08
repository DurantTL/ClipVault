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

  let scanner = SourceScanner()
  let bookmarks = SecurityScopedBookmarkManager()
  let ingestService = IngestService()

  init() {
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
      videos = try scanner.scan(source: sourceURL, includeProxyFiles: settings.includeProxyFiles)
      sessions = buildSessions(from: videos, source: sourceURL)
      updateFreeSpace()
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

  var selectedVideos: [SourceVideo] {
    let selectedIDs = Set(sessions.filter { $0.selected }.flatMap { $0.clips.map(\.id) })
    return videos.filter { video in
      sessions.isEmpty || selectedIDs.contains(video.id)
    }
  }

  var selectedTotalSize: Int64 { selectedVideos.reduce(0) { $0 + $1.size } }

  var statusMessage: String {
    if let error { return error }
    if let canceledSummary { return canceledSummary }
    if sourceURL == nil { return "No source selected" }
    if destinationURL == nil { return "Destination not selected" }
    if sessions.isEmpty { return "No sessions scanned" }
    if selectedVideos.isEmpty { return "No sessions selected" }
    return "Ready to ingest"
  }

  func selectAllSessions() { for index in sessions.indices { sessions[index].selected = true } }
  func clearSessionSelection() { for index in sessions.indices { sessions[index].selected = false } }
  func selectTodaySessions() {
    for index in sessions.indices { sessions[index].selected = Calendar.current.isDateInToday(sessions[index].date) }
  }
  func selectNewOnlySessions() { selectAllSessions() }

  func setSession(_ session: IngestSession, selected: Bool) {
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
    sessions[index].selected = selected
  }

  private func buildSessions(from videos: [SourceVideo], source: URL) -> [IngestSession] {
    let sorted = videos.sorted { ($0.createdAt ?? $0.modifiedAt ?? .distantPast) < ($1.createdAt ?? $1.modifiedAt ?? .distantPast) }
    var groups: [[SourceVideo]] = []
    for video in sorted {
      let date = video.createdAt ?? video.modifiedAt ?? filenameDate(video.url.lastPathComponent) ?? .distantPast
      if let lastGroup = groups.last, let previous = lastGroup.last {
        let previousDate = previous.createdAt ?? previous.modifiedAt ?? filenameDate(previous.url.lastPathComponent) ?? .distantPast
        if Calendar.current.isDate(date, inSameDayAs: previousDate) && date.timeIntervalSince(previousDate) <= 90 * 60 {
          groups[groups.count - 1].append(video)
        } else {
          groups.append([video])
        }
      } else {
        groups.append([video])
      }
    }
    return groups.map { group in
      let dates = group.map { $0.createdAt ?? $0.modifiedAt ?? filenameDate($0.url.lastPathComponent) ?? Date() }.sorted()
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
