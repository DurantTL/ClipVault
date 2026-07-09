import AppKit
import Foundation
import SwiftUI

enum ClipSortOption: String, CaseIterable, Identifiable {
  case ingestOrder = "Ingest Order"
  case shotTime = "Shot Time"
  case filename = "Filename"
  case createdDate = "Created Date"
  case modifiedDate = "Modified Date"
  case duration = "Duration"
  case fileSize = "File Size"
  case cullStatus = "Cull Status"
  case ratingKeepStatus = "Rating/Keep Status"
  case cameraType = "Camera Type"

  var id: String { rawValue }
}

@MainActor final class LibraryViewModel: ObservableObject {
  @Published var project: ClipVaultProject
  @Published var selectedClipID: UUID?
  @Published var selectedClipIDs: Set<UUID> = []
  @Published var filter: String = "All Clips"
  @Published var sortOption: ClipSortOption = .shotTime
  @Published var sortAscending = true
  @AppStorage("libraryInspectorVisible") var inspectorVisible = true
  @Published var previewClip: Clip?
  @Published var thumbnailSize: Double = 190

  let store = ProjectStore()
  let mover = FileMoveService()
  let security = SecurityScopedBookmarkManager()
  let analysis = LocalAnalysisService()
  private let thumbnails = ThumbnailService()
  private var accessedSecurityScopedURLs: [URL] = []
  private var thumbnailGenerationTask: Task<Void, Never>?
  private var queuedThumbnailIDs: Set<UUID> = []

  init(project: ClipVaultProject) {
    self.project = project
    self.project.lastOpenedAt = Date()
    self.selectedClipID = project.clips.first(where: { $0.copyStatus == .copied || $0.verificationStatus == .verified })?.id ?? project.clips.first?.id
    self.selectedClipIDs = Set(project.clips.prefix(1).map(\.id))
    restoreSecurityScopedAccess()
    applyAutomaticTags()
    normalizeExistingThumbnailPaths()
    save()
  }

  var selectedClip: Clip? { project.clips.first { $0.id == selectedClipID } }

  var productionTags: [String] {
    Array(Set(project.defaultTags + project.clips.flatMap { $0.productionTags + $0.automaticTags })).sorted()
  }

  var smartFolders: [String] {
    [
      "All Clips", "Unrated", "Keep", "Maybe", "Reject", "4K", "60p", "Has Audio", "No Audio",
      "Short Clips", "Long Clips", "Large Files", "Sony", "Canon/DCF", "Recently Ingested", "Failed Preview",
      "Failed Verification", "Social Candidates", "Interviews", "B-Roll", "Sermon",
      "Possibly Out of Focus", "Faces", "Group Shots", "Close Faces", "Low Face Visibility",
      "Possibly Shaky", "Stable Clips", "High Motion", "Dark Clips", "Bright Clips",
      "Low Contrast", "Sharp Clips", "Balanced Exposure", "Warm Color", "Cool Color", "Approx. WB", "Failed Analysis"
    ]
  }

  var filteredClips: [Clip] {
    let clips = project.clips.filter(matchesFilter)
    return sorted(clips)
  }

  var selectionCount: Int { selectedClipIDs.isEmpty ? (selectedClipID == nil ? 0 : 1) : selectedClipIDs.count }

  func setStatus(_ status: CullStatus) {
    updateSelected { $0.cullStatus = status }
    if AppSettings.autoAdvanceAfterRating { advanceAfterRating() }
  }

  func updateSelected(_ edit: (inout Clip) -> Void) {
    let ids = activeSelectionIDs
    for id in ids {
      guard let index = project.clips.firstIndex(where: { $0.id == id }) else { continue }
      edit(&project.clips[index])
    }
    save()
  }

  func select(_ clip: Clip, extending: Bool = false) {
    selectedClipID = clip.id
    if extending {
      if selectedClipIDs.contains(clip.id) {
        selectedClipIDs.remove(clip.id)
      } else {
        selectedClipIDs.insert(clip.id)
      }
    } else {
      selectedClipIDs = [clip.id]
    }
  }

  func selectNext() { select(offset: 1) }
  func selectPrevious() { select(offset: -1) }

  private func select(offset: Int) {
    let clips = filteredClips
    guard !clips.isEmpty else { return }
    let current = selectedClipID.flatMap { id in clips.firstIndex { $0.id == id } } ?? 0
    let nextIndex = min(max(current + offset, 0), clips.count - 1)
    select(clips[nextIndex])
  }

  func previewSelected() {
    guard let clip = selectedClip else { return }
    if canPreview(clip) {
      previewClip = clip
    } else {
      logPreviewFailure(for: clip, reason: previewFailureMessage(for: clip))
      previewClip = clip
    }
  }

  func resolvedMediaURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL? {
    let project = project ?? self.project
    let candidates = mediaURLCandidates(for: clip, in: project)
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
  }


  func thumbnailURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL {
    let project = project ?? self.project
    return security.projectFolderURL(for: project)
      .appendingPathComponent(".clipvault-cache", isDirectory: true)
      .appendingPathComponent("thumbnails", isDirectory: true)
      .appendingPathComponent(clip.id.uuidString)
      .appendingPathExtension("jpg")
  }

  func existingThumbnailURL(for clip: Clip, in project: ClipVaultProject? = nil) -> URL? {
    let project = project ?? self.project
    if let path = clip.thumbnailPath, !path.isEmpty {
      let url = path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : security.projectFolderURL(for: project).appendingPathComponent(path)
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    let cacheURL = thumbnailURL(for: clip, in: project)
    return FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil
  }

  func queueThumbnailGenerationIfNeeded(for clip: Clip) {
    guard clip.copyStatus != .pending, clip.copyStatus != .copying else { return }
    guard existingThumbnailURL(for: clip) == nil else { return }
    guard resolvedMediaURL(for: clip) != nil else { return }
    guard clip.thumbnailStatus != .generating else { return }
    queueThumbnailGeneration(for: [clip.id], force: false)
  }

  func generateMissingThumbnails() {
    let ids = project.clips.filter { clip in
      clip.copyStatus != .pending &&
        clip.copyStatus != .copying &&
        existingThumbnailURL(for: clip) == nil &&
        resolvedMediaURL(for: clip) != nil
    }.map(\.id)
    queueThumbnailGeneration(for: ids, force: false)
  }

  func regenerateThumbnailForSelectedClip() {
    guard let selectedClipID else { return }
    queueThumbnailGeneration(for: [selectedClipID], force: true)
  }

  func regenerateThumbnailsForSelectedClips() {
    queueThumbnailGeneration(for: Array(activeSelectionIDs), force: true)
  }

  func canPreview(_ clip: Clip) -> Bool {
    guard clip.copyStatus == .copied || clip.verificationStatus == .copied || clip.verificationStatus == .verified || clip.copyStatus == .failed else {
      return false
    }
    return resolvedMediaURL(for: clip) != nil
  }

  func previewFailureMessage(for clip: Clip) -> String {
    if clip.copyStatus == .pending || clip.copyStatus == .copying || clip.copyStatus == .skipped {
      return "Could not preview this clip. It is pending/not copied yet."
    }
    let candidates = mediaURLCandidates(for: clip, in: project)
    if candidates.isEmpty {
      return "Could not preview this clip. No destination path is stored."
    }
    if candidates.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) && FileManager.default.fileExists(atPath: $0.path) }) {
      return "Could not preview this clip. Permission denied."
    }
    return "Could not preview this clip. The file is missing or uses an unsupported codec."
  }

  func logPreviewFailure(for clip: Clip, reason: String, avPlayerError: Error? = nil) {
    let url = resolvedMediaURL(for: clip)
    let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    print("""
    ClipVault preview failure: filename=\(clip.currentFilename), reason=\(reason), resolvedURL=\(url?.path ?? "nil"), fileExists=\(exists), copyStatus=\(clip.copyStatus.rawValue), verificationStatus=\(clip.verificationStatus.rawValue), thumbnailStatus=\(clip.thumbnailStatus.rawValue), avPlayerError=\(avPlayerError?.localizedDescription ?? "none")
    """)
  }

  func closePreview() { previewClip = nil }

  func addFolder(_ name: String) {
    let folder = SafeFilename.safeFolderName(name)
    if !folder.isEmpty && !project.customFolders.contains(folder) {
      project.customFolders.append(folder)
      save()
    }
  }

  func renameFolder(_ folder: String, to newName: String) {
    let clean = SafeFilename.safeFolderName(newName)
    guard !clean.isEmpty, let index = project.customFolders.firstIndex(of: folder) else { return }
    project.customFolders[index] = clean
    for i in project.clips.indices where project.clips[i].assignedFolder == folder {
      project.clips[i].assignedFolder = clean
    }
    save()
  }

  func deleteFolder(_ folder: String) {
    project.customFolders.removeAll { $0 == folder }
    for i in project.clips.indices where project.clips[i].assignedFolder == folder {
      project.clips[i].assignedFolder = nil
    }
    save()
  }

  func moveSelected(to folder: String) {
    for id in activeSelectionIDs {
      guard let i = project.clips.firstIndex(where: { $0.id == id }) else { continue }
      do {
        try mover.move(
          clip: &project.clips[i], to: folder, projectFolder: security.projectFolderURL(for: project))
      } catch {
        project.clips[i].errorMessage = error.localizedDescription
      }
    }
    save()
  }

  func undoMove() {
    do {
      try mover.undo(project: &project)
      save()
    } catch {}
  }

  func reveal() {
    let urls = activeSelectionIDs.compactMap { id -> URL? in
      guard let clip = project.clips.first(where: { $0.id == id }) else { return nil }
      return resolvedMediaURL(for: clip)
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [security.projectFolderURL(for: project)] : urls)
  }

  func resumeIngest() {
    Task {
      project.ingestStatus = .inProgress
      project.canResumeIngest = true
      save()
      for index in project.clips.indices {
        guard project.clips[index].verificationStatus != .verified else { continue }
        let sourcePath = project.clips[index].sourcePath.isEmpty ? project.clips[index].originalSourcePath : project.clips[index].sourcePath
        guard !sourcePath.isEmpty, FileManager.default.fileExists(atPath: sourcePath) else {
          project.clips[index].errorMessage = "Source is not connected. Reconnect the SD card or choose a new source folder to resume."
          project.clips[index].copyStatus = .failed
          save()
          continue
        }
        do {
          let destination = URL(fileURLWithPath: project.clips[index].currentPath)
          try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: destination)
          }
          project.clips[index].copyStatus = .copied
          project.clips[index].verificationStatus = .verified
          project.clips[index].errorMessage = nil
        } catch {
          project.clips[index].copyStatus = .failed
          project.clips[index].verificationStatus = .failed
          project.clips[index].errorMessage = error.localizedDescription
        }
        refreshProjectCounts()
        save()
      }
      refreshProjectCounts()
      project.ingestStatus = project.pendingClipCount == 0 && project.failedClipCount == 0 ? .complete : .incomplete
      project.canResumeIngest = project.ingestStatus.canResume
      save()
    }
  }

  private func refreshProjectCounts() {
    project.totalSelectedClips = max(project.totalSelectedClips, project.clips.count)
    project.copiedClipCount = project.clips.filter { $0.copyStatus == .copied || $0.verificationStatus == .verified }.count
    project.verifiedClipCount = project.clips.filter { $0.verificationStatus == .verified }.count
    project.failedClipCount = project.clips.filter { $0.copyStatus == .failed || $0.verificationStatus == .failed }.count
    project.pendingClipCount = project.clips.filter { $0.copyStatus == .pending || $0.copyStatus == .copying }.count
    project.lastIngestDate = Date()
  }

  func revealProject() {
    NSWorkspace.shared.activateFileViewerSelecting([security.projectFolderURL(for: project)])
  }

  func copySelectedFilenames() {
    let names = activeSelectionIDs.compactMap { id in project.clips.first { $0.id == id }?.currentFilename }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
  }

  func addProductionTagToSelection(_ tag: String) {
    let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    updateSelected { clip in
      if !clip.productionTags.contains(clean) { clip.productionTags.append(clean) }
    }
  }

  func analyzeLocally(mode: LocalAnalysisMode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Off") ?? .off) {
    guard mode != .off else { return }
    Task {
      for index in project.clips.indices {
        project.clips[index] = await analysis.analyzed(project.clips[index], mode: mode)
        save()
      }
    }
  }

  func analyzeVisibleClips() {
    let ids = Set(filteredClips.map(\.id))
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    Task {
      for index in project.clips.indices where ids.contains(project.clips[index].id) {
        project.clips[index] = await analysis.analyzed(project.clips[index], mode: mode)
        save()
      }
    }
  }

  func analyzeSelectedClip() {
    guard let selectedClipID, let index = project.clips.firstIndex(where: { $0.id == selectedClipID }) else { return }
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    Task {
      project.clips[index] = await analysis.analyzed(project.clips[index], mode: mode)
      save()
    }
  }

  func exportClipReport(keepsOnly: Bool = false) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = keepsOnly ? "ClipVault-Keep-List.csv" : "ClipVault-Clip-Report.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let clips = project.clips.filter { !keepsOnly || $0.cullStatus == .keep }
    try? csv(for: clips).write(to: url, atomically: true, encoding: .utf8)
  }

  func exportProjectMetadata() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "ClipVault-Project-Metadata.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if let data = try? JSONEncoder().encode(project) { try? data.write(to: url) }
  }

  func save() { try? store.save(project) }


  private func queueThumbnailGeneration(for ids: [UUID], force: Bool) {
    let newIDs = ids.filter { id in
      guard let clip = project.clips.first(where: { $0.id == id }) else { return false }
      guard clip.copyStatus != .pending, clip.copyStatus != .copying else { return false }
      guard resolvedMediaURL(for: clip) != nil else { return false }
      return force || existingThumbnailURL(for: clip) == nil
    }
    guard !newIDs.isEmpty else { return }
    queuedThumbnailIDs.formUnion(newIDs)
    if thumbnailGenerationTask == nil {
      thumbnailGenerationTask = Task { [weak self] in
        await self?.processThumbnailQueue()
      }
    }
  }

  private func processThumbnailQueue() async {
    defer { thumbnailGenerationTask = nil }
    while let id = queuedThumbnailIDs.first {
      queuedThumbnailIDs.remove(id)
      guard let index = project.clips.firstIndex(where: { $0.id == id }) else { continue }
      let clip = project.clips[index]
      guard let mediaURL = resolvedMediaURL(for: clip) else { continue }

      let cacheURL = thumbnailURL(for: clip)
      project.clips[index].thumbnailStatus = .generating
      project.clips[index].thumbnailErrorMessage = nil
      save()

      do {
        if FileManager.default.fileExists(atPath: cacheURL.path) {
          project.clips[index].thumbnailPath = relativePath(for: cacheURL)
          project.clips[index].thumbnailStatus = .generated
          save()
          continue
        }

        let quality = ThumbnailQuality(rawValue: UserDefaults.standard.string(forKey: "thumbnailQuality") ?? "balanced") ?? .balanced
        let result = try await thumbnails.generate(
          for: clip,
          mediaURL: mediaURL,
          project: project,
          quality: quality
        )
        if let updatedIndex = project.clips.firstIndex(where: { $0.id == id }) {
          project.clips[updatedIndex].thumbnailPath = result.relativePath
          project.clips[updatedIndex].thumbnailStatus = .generated
          project.clips[updatedIndex].thumbnailErrorMessage = nil
          save()
        }
      } catch {
        if let failedIndex = project.clips.firstIndex(where: { $0.id == id }) {
          project.clips[failedIndex].thumbnailStatus = .failed
          project.clips[failedIndex].thumbnailErrorMessage = error.localizedDescription
          save()
        }
      }
    }
  }

  private func normalizeExistingThumbnailPaths() {
    for index in project.clips.indices {
      if let url = existingThumbnailURL(for: project.clips[index]) {
        project.clips[index].thumbnailPath = relativePath(for: url)
        if project.clips[index].thumbnailStatus == .pending {
          project.clips[index].thumbnailStatus = .generated
        }
      }
    }
  }

  private func relativePath(for url: URL) -> String {
    let projectFolder = security.projectFolderURL(for: project)
    let prefix = projectFolder.path + "/"
    if url.path.hasPrefix(prefix) {
      return String(url.path.dropFirst(prefix.count))
    }
    return url.path
  }

  private var activeSelectionIDs: Set<UUID> {
    selectedClipIDs.isEmpty ? Set(selectedClipID.map { [$0] } ?? []) : selectedClipIDs
  }

  private func advanceAfterRating() {
    if AppSettings.advanceDirectionPrevious { selectPrevious() } else { selectNext() }
  }

  private func applyAutomaticTags() {
    for index in project.clips.indices {
      project.clips[index].automaticTags = analysis.tags(for: project.clips[index])
    }
  }

  private func matchesFilter(_ clip: Clip) -> Bool {
    switch filter {
    case "All Clips": return true
    case "Unrated": return clip.cullStatus == .unrated
    case "Keep": return clip.cullStatus == .keep
    case "Maybe": return clip.cullStatus == .maybe
    case "Reject": return clip.cullStatus == .reject
    case "Verified": return clip.verificationStatus == .verified
    case "Failed", "Failed Verification": return clip.verificationStatus == .failed
    case "Has Audio": return clip.hasAudio == true || clip.automaticTags.contains("Has Audio")
    case "No Audio": return clip.hasAudio == false || clip.automaticTags.contains("No Audio")
    case "Short Clip", "Short Clips": return (clip.duration ?? .infinity) < 30 || clip.automaticTags.contains("Short Clip")
    case "Long Clip", "Long Clips": return (clip.duration ?? 0) >= 300 || clip.automaticTags.contains("Long Clip")
    case "Large Files": return clip.fileSize >= 5_000_000_000 || clip.automaticTags.contains("Large File")
    case "Recently Ingested": return clip.ingestDate.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 99 <= 7 } ?? false
    case "Failed Preview": return clip.previewUnavailable || clip.thumbnailPath == nil
    case "Canon/DCF": return clip.automaticTags.contains("Canon/DCF") || clip.originalSourcePath.localizedCaseInsensitiveContains("/DCIM/")
    case "Possibly Out of Focus", "Faces", "Group Shots", "Close Faces", "Low Face Visibility", "Possibly Shaky", "Stable Clips", "High Motion", "Dark Clips", "Bright Clips", "Low Contrast", "Sharp Clips", "Balanced Exposure", "Warm Color", "Cool Color", "Approx. WB", "Failed Analysis": return clip.automaticTags.contains(filter)
    case "Social Candidates": return clip.isSocialClipCandidate
    case "Interviews": return clip.isInterview
    case "B-Roll": return clip.isBroll || clip.assignedFolder == filter
    case "Sermon": return clip.isSermon || clip.assignedFolder == filter
    default:
      return clip.assignedFolder == filter || clip.productionTags.contains(filter) || clip.automaticTags.contains(filter)
    }
  }

  private func sorted(_ clips: [Clip]) -> [Clip] {
    let sorted: [Clip]
    switch sortOption {
    case .ingestOrder: sorted = clips.sorted { ($0.ingestDate ?? .distantPast) < ($1.ingestDate ?? .distantPast) }
    case .shotTime: sorted = clips.sorted { ($0.effectiveShotTime ?? $0.ingestDate ?? .distantPast) < ($1.effectiveShotTime ?? $1.ingestDate ?? .distantPast) }
    case .filename: sorted = clips.sorted { $0.currentFilename.localizedStandardCompare($1.currentFilename) == .orderedAscending }
    case .createdDate: sorted = clips.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    case .modifiedDate: sorted = clips.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
    case .duration: sorted = clips.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
    case .fileSize: sorted = clips.sorted { $0.fileSize < $1.fileSize }
    case .cullStatus, .ratingKeepStatus: sorted = clips.sorted { $0.cullStatus.rawValue < $1.cullStatus.rawValue }
    case .cameraType: sorted = clips.sorted { ($0.cardVolumeName ?? "").localizedStandardCompare($1.cardVolumeName ?? "") == .orderedAscending }
    }
    return sortAscending ? sorted : Array(sorted.reversed())
  }

  private func mediaURLCandidates(for clip: Clip, in project: ClipVaultProject) -> [URL] {
    var urls: [URL] = []
    func appendPath(_ path: String) {
      guard !path.isEmpty else { return }
      let url = URL(fileURLWithPath: path)
      if !urls.contains(url) { urls.append(url) }
    }

    appendPath(clip.currentPath)

    let projectFolder = security.projectFolderURL(for: project)
    if !clip.destinationRelativePath.isEmpty {
      urls.append(projectFolder.appendingPathComponent(clip.destinationRelativePath))
    }
    if !clip.relativePath.isEmpty {
      urls.append(projectFolder.appendingPathComponent(clip.relativePath))
    }
    return urls.reduce(into: []) { unique, url in
      if !unique.contains(url) { unique.append(url) }
    }
  }

  private func restoreSecurityScopedAccess() {
    let bookmarks: [Data] = [
      project.projectFolderBookmarkData,
      project.destinationBookmarkData,
      project.canResumeIngest ? project.sourceBookmarkData : nil
    ].compactMap { $0 }

    for bookmark in bookmarks {
      guard let url = try? security.resolve(bookmark) else { continue }
      if url.startAccessingSecurityScopedResource() {
        accessedSecurityScopedURLs.append(url)
      }
    }
  }

  deinit {
    for url in accessedSecurityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func csv(for clips: [Clip]) -> String {
    let header = "filename,cull status,duration,size,resolution,frame rate,codec,tags,notes,source path,destination path"
    let rows = clips.map { clip in
      [
        clip.currentFilename,
        clip.cullStatus.label,
        DurationFormatterUtil.string(clip.duration),
        FileSizeFormatterUtil.string(clip.fileSize),
        "\(clip.width.map(String.init) ?? "?")x\(clip.height.map(String.init) ?? "?")",
        clip.frameRate.map { String(format: "%.2f", $0) } ?? "",
        clip.codec ?? "",
        clip.productionTags.joined(separator: "; "),
        clip.customNotes,
        clip.originalSourcePath,
        clip.currentPath
      ].map(escapeCSV).joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n")
  }

  private func escapeCSV(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
