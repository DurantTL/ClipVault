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
  case rating = "Star Rating"
  case qualityScore = "Analysis Quality"
  case cameraType = "Camera Type"

  var id: String { rawValue }
}

enum ClipReportKind {
  case allClips
  case keeps
  case rejects
  case verification
  case analysis

  var defaultFilename: String {
    switch self {
    case .allClips: return "\(AppBrand.appName)-Clip-Report.csv"
    case .keeps: return "\(AppBrand.appName)-Keep-List.csv"
    case .rejects: return "\(AppBrand.appName)-Reject-List.csv"
    case .verification: return "\(AppBrand.appName)-Verification-Report.csv"
    case .analysis: return "\(AppBrand.appName)-Analysis-Report.csv"
    }
  }
}

enum EditFolderExportScope {
  case keeps
  case keepsAndMaybes
  case fourPlusStars
  case selected

  var label: String {
    switch self {
    case .keeps: return "Keeps"
    case .keepsAndMaybes: return "Keep + Maybe"
    case .fourPlusStars: return "4–5 Star Clips"
    case .selected: return "Selected Clips"
    }
  }
}

struct BatchMetadataEdit {
  enum TagMode: String, CaseIterable, Identifiable {
    case append = "Append"
    case replace = "Replace"
    case remove = "Remove"
    var id: String { rawValue }
  }

  enum FlagAction: String, CaseIterable, Identifiable {
    case leave = "Leave"
    case set = "Set"
    case clear = "Clear"
    var id: String { rawValue }
  }

  var tagsText = ""
  var tagMode: TagMode = .append
  var peopleText = ""
  var location = ""
  var scene = ""
  var shotType = ""
  var notes = ""
  var favorite: FlagAction = .leave
  var broll: FlagAction = .leave
  var sermon: FlagAction = .leave
  var interview: FlagAction = .leave
  var socialClipCandidate: FlagAction = .leave

  var parsedTags: [String] {
    tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  var parsedPeople: [String] {
    peopleText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }
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
  @Published var exportProgress: ClipExportProgress?
  @Published var exportSummary: ClipExportSummary?
  @Published var aliasSummary: AliasCreationSummary?
  private var selectionAnchorID: UUID?
  private let exporter = ClipExportService()
  private let aliases = AliasService()

  let store = ProjectStore()
  let mover = FileMoveService()
  let security = SecurityScopedBookmarkManager()
  let analysis = LocalAnalysisService()
  private let ingestService = IngestService()
  private let thumbnails = ThumbnailService()
  private var accessedSecurityScopedURLs: [URL] = []
  private var thumbnailGenerationTask: Task<Void, Never>?
  private var analysisTask: Task<Void, Never>?
  private var queuedThumbnailIDs: Set<UUID> = []
  private var forcedThumbnailIDs: Set<UUID> = []

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
      "Unrated", "Keep", "Maybe", "Reject", "Needs Review"
    ]
  }

  var filteredClips: [Clip] {
    let clips = project.clips.filter { matchesFilter($0) }
    return sorted(clips)
  }

  /// The sidebar keeps workflow filters intentionally small. Everything more
  /// specific is a tag or a project folder, which keeps the library readable
  /// as analysis and metadata grow.
  func clipCount(for filter: String) -> Int {
    project.clips.filter { matchesFilter($0, filter: filter) }.count
  }

  func previewNeighborURLs(for clip: Clip) -> [URL] {
    let clips = filteredClips
    guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return [] }
    let nearby = [index - 1, index + 1, index + 2].compactMap { clips.indices.contains($0) ? clips[$0] : nil }
    return nearby.compactMap { candidate in
      canPreview(candidate) ? resolvedMediaURL(for: candidate) : nil
    }
  }

  var selectionCount: Int { selectedClipIDs.isEmpty ? (selectedClipID == nil ? 0 : 1) : selectedClipIDs.count }

  func setStatus(_ status: CullStatus) {
    updateSelected { $0.applyCullStatus(status) }
    if AppSettings.autoAdvanceAfterRating { advanceAfterRating() }
  }

  func setRating(_ value: Int) {
    updateSelected { $0.applyRating(value) }
    if AppSettings.autoAdvanceAfterRating { advanceAfterRating() }
  }

  /// Applies analysis-suggested ratings, but only to clips the user has not
  /// rated yet. Suggestions never overwrite a human decision.
  func applySuggestedRatingsToUnrated() {
    for index in project.clips.indices {
      let clip = project.clips[index]
      guard clip.rating == 0, clip.cullStatus == .unrated, let suggested = clip.suggestedRating else { continue }
      project.clips[index].applyRating(suggested)
    }
    save()
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
      selectionAnchorID = clip.id
    }
  }

  /// Shift-click: selects every visible clip between the selection anchor
  /// (the last plain click) and the clicked clip.
  func selectRange(to clip: Clip) {
    let clips = filteredClips
    guard let clickedIndex = clips.firstIndex(where: { $0.id == clip.id }) else { return }
    let anchorID = selectionAnchorID ?? selectedClipID
    guard let anchorIndex = anchorID.flatMap({ id in clips.firstIndex { $0.id == id } }) else {
      select(clip)
      return
    }
    let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
    selectedClipIDs.formUnion(clips[range].map(\.id))
    selectedClipID = clip.id
  }

  func selectAllVisible() {
    let clips = filteredClips
    selectedClipIDs = Set(clips.map(\.id))
    if selectedClipID == nil { selectedClipID = clips.first?.id }
  }

  /// Escape: collapses a multi-selection back to the focused clip.
  func clearMultiSelection() {
    selectedClipIDs = Set(selectedClipID.map { [$0] } ?? [])
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
      .appendingPathComponent(AppBrand.cacheFolderName, isDirectory: true)
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
    Preview failure: filename=\(clip.currentFilename), reason=\(reason), resolvedURL=\(url?.path ?? "nil"), fileExists=\(exists), copyStatus=\(clip.copyStatus.rawValue), verificationStatus=\(clip.verificationStatus.rawValue), thumbnailStatus=\(clip.thumbnailStatus.rawValue), avPlayerError=\(avPlayerError?.localizedDescription ?? "none")
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
      do {
        project = try await ingestService.resume(
          project: project,
          settings: AppSettings()
        ) { _ in }
      } catch {
        for index in project.clips.indices where project.clips[index].verificationStatus != .verified {
          project.clips[index].errorMessage = error.localizedDescription
        }
        project.ingestStatus = .incomplete
        project.canResumeIngest = true
        save()
      }
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

  func createAliases(named folderName: String) {
    let items = activeSelectionIDs.compactMap { id -> (clip: Clip, mediaURL: URL)? in
      guard let clip = project.clips.first(where: { $0.id == id }),
        (clip.copyStatus == .copied || clip.verificationStatus == .verified),
        let mediaURL = resolvedMediaURL(for: clip) else { return nil }
      return (clip, mediaURL)
    }
    guard !items.isEmpty else { return }
    aliasSummary = aliases.createAliases(
      named: folderName,
      for: items,
      projectFolder: security.projectFolderURL(for: project))
  }

  func revealAliases() {
    NSWorkspace.shared.activateFileViewerSelecting([aliases.aliasesFolder(in: security.projectFolderURL(for: project))])
  }

  func handOffEditFolder(to applicationIdentifier: String?) {
    let panel = NSOpenPanel()
    panel.title = "Choose Edit Folder"
    panel.message = "Choose the folder \(AppBrand.appName) should reveal or open in your editor."
    panel.prompt = applicationIdentifier == nil ? "Reveal" : "Open"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let folder = panel.url else { return }

    guard let applicationIdentifier else {
      NSWorkspace.shared.activateFileViewerSelecting([folder])
      return
    }
    guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationIdentifier) else {
      let alert = NSAlert()
      alert.messageText = "Editor not found"
      alert.informativeText = "Install the selected editor, then try the handoff again."
      alert.runModal()
      return
    }
    NSWorkspace.shared.open([folder], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
  }

  func addProductionTagToSelection(_ tag: String) {
    let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    updateSelected { clip in
      if !clip.productionTags.contains(clean) { clip.productionTags.append(clean) }
    }
  }

  func removeProductionTagFromSelection(_ tag: String) {
    updateSelected { clip in
      clip.productionTags.removeAll { $0 == tag }
    }
  }

  /// Tags present on any clip in the current selection, for the Remove Tag menu.
  var productionTagsInSelection: [String] {
    let ids = activeSelectionIDs
    let tags = project.clips.filter { ids.contains($0.id) }.flatMap(\.productionTags)
    return Array(Set(tags)).sorted()
  }

  func applyBatchMetadata(_ edit: BatchMetadataEdit) {
    let tags = edit.parsedTags
    let people = edit.parsedPeople
    updateSelected { clip in
      switch edit.tagMode {
      case .append:
        for tag in tags where !clip.productionTags.contains(tag) { clip.productionTags.append(tag) }
      case .replace:
        if !tags.isEmpty { clip.productionTags = tags }
      case .remove:
        clip.productionTags.removeAll { tags.contains($0) }
      }
      for person in people where !clip.people.contains(person) { clip.people.append(person) }
      if !edit.location.isEmpty { clip.location = edit.location }
      if !edit.scene.isEmpty { clip.scene = edit.scene }
      if !edit.shotType.isEmpty { clip.shotType = edit.shotType }
      if !edit.notes.isEmpty { clip.customNotes = edit.notes }
      apply(edit.favorite, to: &clip.favorite)
      apply(edit.broll, to: &clip.isBroll)
      apply(edit.sermon, to: &clip.isSermon)
      apply(edit.interview, to: &clip.isInterview)
      apply(edit.socialClipCandidate, to: &clip.isSocialClipCandidate)
    }
  }

  private func apply(_ action: BatchMetadataEdit.FlagAction, to flag: inout Bool) {
    switch action {
    case .leave: break
    case .set: flag = true
    case .clear: flag = false
    }
  }

  func copyToEditFolder(_ scope: EditFolderExportScope) {
    let clips = exportableClips(for: scope)
    guard !clips.isEmpty else {
      let alert = NSAlert()
      alert.messageText = "No clips to copy"
      alert.informativeText = "No copied clips match \(scope.label). Rate or select clips first, and make sure they finished copying."
      alert.runModal()
      return
    }
    let panel = NSOpenPanel()
    panel.title = "Choose Edit Folder"
    panel.message = "\(AppBrand.appName) will copy \(clips.count) clip\(clips.count == 1 ? "" : "s") (\(scope.label)) into this folder. Nothing is moved or overwritten."
    panel.prompt = "Copy Here"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    let items = clips.compactMap { clip -> (clip: Clip, mediaURL: URL)? in
      guard let url = resolvedMediaURL(for: clip) else { return nil }
      return (clip, url)
    }
    exportSummary = nil
    exportProgress = ClipExportProgress(completed: 0, total: items.count, currentFilename: "")
    Task { [weak self] in
      guard let self else { return }
      let summary = await self.exporter.copyClips(items, to: destination) { progress in
        self.exportProgress = progress
      }
      self.exportProgress = nil
      self.exportSummary = summary
      NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
  }

  private func exportableClips(for scope: EditFolderExportScope) -> [Clip] {
    let eligible = filteredClipsForExport
    switch scope {
    case .keeps: return eligible.filter { $0.cullStatus == .keep }
    case .keepsAndMaybes: return eligible.filter { $0.cullStatus == .keep || $0.cullStatus == .maybe }
    case .fourPlusStars: return eligible.filter { $0.rating >= 4 }
    case .selected:
      let ids = activeSelectionIDs
      return eligible.filter { ids.contains($0.id) }
    }
  }

  /// Only copied project media leaves the project. Pending or failed clips
  /// never export, so no export can ever read from a source card.
  private var filteredClipsForExport: [Clip] {
    project.clips.filter { clip in
      (clip.copyStatus == .copied || clip.verificationStatus == .verified) && resolvedMediaURL(for: clip) != nil
    }
  }

  /// Fast, non-destructive duplicate detection for a large project. Candidates
  /// share an original filename and byte size; no media is read or altered.
  func findDuplicateCandidates() {
    let copied = project.clips.filter { $0.verificationStatus == .verified }
    let groups = Dictionary(grouping: copied) { clip in
      "\(clip.originalFilename.localizedLowercase)|\(clip.fileSize)"
    }
    let candidateIDs = Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    for index in project.clips.indices {
      project.clips[index].automaticTags.removeAll { $0 == "Duplicate Candidate" }
      if candidateIDs.contains(project.clips[index].id) {
        project.clips[index].automaticTags.append("Duplicate Candidate")
      }
    }
    filter = candidateIDs.isEmpty ? "All Clips" : "Duplicate Candidates"
    save()
  }

  func analyzeLocally(mode: LocalAnalysisMode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Off") ?? .off) {
    analyzeClips(ids: Array(activeSelectionIDs), requestedMode: mode)
  }

  func analyzeVisibleClips() {
    let ids = filteredClips.map(\.id)
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    analyzeClips(ids: ids, requestedMode: mode)
  }

  func analyzeSelectedClip() {
    guard let selectedClipID else { return }
    let mode = LocalAnalysisMode(rawValue: UserDefaults.standard.string(forKey: "localAnalysisMode") ?? "Fast") ?? .fast
    analyzeClips(ids: [selectedClipID], requestedMode: mode)
  }

  func cancelAnalysis() {
    analysisTask?.cancel()
    analysisTask = nil
  }

  private func analyzeClips(ids: [UUID], requestedMode: LocalAnalysisMode) {
    let tuning = AppSettings().performanceTuning()
    let mode = requestedMode == .off ? tuning.analysisMode : requestedMode
    guard mode != .off else { return }
    analysisTask?.cancel()
    let orderedIDs = prioritize(ids: ids)
    analysisTask = Task(priority: tuning.backgroundPriority) { [weak self] in
      guard let self else { return }
      for id in orderedIDs {
        if Task.isCancelled { break }
        guard let index = self.project.clips.firstIndex(where: { $0.id == id }) else { continue }
        let clip = self.project.clips[index]
        guard clip.copyStatus != .pending, clip.copyStatus != .copying else { continue }
        guard self.resolvedMediaURL(for: clip) != nil else { continue }
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .localAnalysis, label: clip.currentFilename)
        let start = Date()
        let analyzed = await self.analysis.analyzed(clip, mode: mode)
        await BackgroundWorkCoordinator.shared.finish(workID)
        PerformanceLogger.shared.analysis(duration: Date().timeIntervalSince(start), filename: clip.currentFilename, failed: analyzed.analysisStatus == .failed)
        if let updatedIndex = self.project.clips.firstIndex(where: { $0.id == id }) {
          self.project.clips[updatedIndex] = analyzed
          self.save()
        }
      }
    }
  }

  private func prioritize(ids: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    var ordered: [UUID] = []
    for id in Array(activeSelectionIDs) + ids {
      if seen.insert(id).inserted { ordered.append(id) }
    }
    return ordered
  }

  func exportClipReport(_ kind: ClipReportKind = .allClips) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = kind.defaultFilename
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let clips: [Clip]
    switch kind {
    case .keeps: clips = project.clips.filter { $0.cullStatus == .keep }
    case .rejects: clips = project.clips.filter { $0.cullStatus == .reject }
    case .allClips, .verification, .analysis: clips = project.clips
    }
    try? csv(for: clips, kind: kind).write(to: url, atomically: true, encoding: .utf8)
  }

  func exportProjectMetadata() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(AppBrand.appName)-Project-Metadata.json"
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
    if force {
      forcedThumbnailIDs.formUnion(newIDs)
    }
    if thumbnailGenerationTask == nil {
      thumbnailGenerationTask = Task { [weak self] in
        await self?.processThumbnailQueue()
      }
    }
  }

  private func processThumbnailQueue() async {
    defer { thumbnailGenerationTask = nil }
    while let id = prioritizedThumbnailID() {
      queuedThumbnailIDs.remove(id)
      let force = forcedThumbnailIDs.remove(id) != nil
      guard let index = project.clips.firstIndex(where: { $0.id == id }) else { continue }
      let clip = project.clips[index]
      guard let mediaURL = resolvedMediaURL(for: clip) else { continue }

      let cacheURL = thumbnailURL(for: clip)
      project.clips[index].thumbnailStatus = .generating
      project.clips[index].thumbnailErrorMessage = nil
      save()

      do {
        if !force, FileManager.default.fileExists(atPath: cacheURL.path) {
          project.clips[index].thumbnailPath = relativePath(for: cacheURL)
          project.clips[index].thumbnailStatus = .generated
          save()
          continue
        }

        let quality = ThumbnailQuality(rawValue: UserDefaults.standard.string(forKey: "thumbnailQuality") ?? "balanced") ?? .balanced
        let workID = await BackgroundWorkCoordinator.shared.begin(kind: .libraryThumbnail, label: clip.currentFilename)
        defer { Task { await BackgroundWorkCoordinator.shared.finish(workID) } }
        let result = try await thumbnails.generate(
          for: clip,
          mediaURL: mediaURL,
          project: project,
          quality: quality,
          force: force
        )
        if let updatedIndex = project.clips.firstIndex(where: { $0.id == id }) {
          project.clips[updatedIndex].thumbnailPath = result.relativePath
          project.clips[updatedIndex].thumbnailStatus = .generated
          project.clips[updatedIndex].thumbnailErrorMessage = nil
          save()
        }
      } catch {
        if let failedIndex = project.clips.firstIndex(where: { $0.id == id }) {
          if FileManager.default.fileExists(atPath: cacheURL.path) {
            project.clips[failedIndex].thumbnailPath = relativePath(for: cacheURL)
            project.clips[failedIndex].thumbnailStatus = .generated
          } else {
            project.clips[failedIndex].thumbnailStatus = .failed
          }
          project.clips[failedIndex].thumbnailErrorMessage = error.localizedDescription
          save()
        }
      }
    }
  }

  private func prioritizedThumbnailID() -> UUID? {
    if let selected = selectedClipID, queuedThumbnailIDs.contains(selected) { return selected }
    if let visible = filteredClips.map(\.id).first(where: { queuedThumbnailIDs.contains($0) }) { return visible }
    return queuedThumbnailIDs.first
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

  private func matchesFilter(_ clip: Clip, filter requestedFilter: String? = nil) -> Bool {
    let activeFilter = requestedFilter ?? self.filter
    switch activeFilter {
    case "All Clips": return true
    case "Unrated": return clip.cullStatus == .unrated
    case "Keep": return clip.cullStatus == .keep
    case "Maybe": return clip.cullStatus == .maybe
    case "Reject": return clip.cullStatus == .reject
    case "Needs Review": return clip.cullStatus == .unrated || clip.analysisStatus == .failed || clip.verificationStatus == .failed
    case "Favorites (5-Star)": return clip.rating == 5
    case "4+ Stars": return clip.rating >= 4
    case "Top Pick Suggestions": return clip.automaticTags.contains("Top Pick Suggestion")
    case "Social Pick Suggestions": return clip.automaticTags.contains("Social Pick Suggestion")
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
    case "Duplicate Candidates": return clip.automaticTags.contains("Duplicate Candidate")
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
    case .cullStatus: sorted = clips.sorted { $0.cullStatus.rawValue < $1.cullStatus.rawValue }
    case .ratingKeepStatus, .rating: sorted = clips.sorted { ($0.rating, $0.cullStatus.rawValue) < ($1.rating, $1.cullStatus.rawValue) }
    case .qualityScore: sorted = clips.sorted { ($0.analysisQualityScore ?? -1) < ($1.analysisQualityScore ?? -1) }
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
    thumbnailGenerationTask?.cancel()
    analysisTask?.cancel()
    for url in accessedSecurityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private struct CSVColumn {
    let title: String
    let value: (Clip) -> String

    init(_ title: String, _ value: @escaping (Clip) -> String) {
      self.title = title
      self.value = value
    }
  }

  private func csv(for clips: [Clip], kind: ClipReportKind = .allClips) -> String {
    let columns = csvColumns(for: kind)
    let header = columns.map(\.title).joined(separator: ",")
    let rows = clips.map { clip in
      columns.map { escapeCSV($0.value(clip)) }.joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n")
  }

  private func csvColumns(for kind: ClipReportKind) -> [CSVColumn] {
    func score(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "" }
    let identity: [CSVColumn] = [
      CSVColumn("filename", { $0.currentFilename }),
      CSVColumn("original filename", { $0.originalFilename })
    ]
    let cull: [CSVColumn] = [
      CSVColumn("cull status", { $0.cullStatus.label }),
      CSVColumn("rating", { String($0.rating) })
    ]
    let technical: [CSVColumn] = [
      CSVColumn("duration", { DurationFormatterUtil.string($0.duration) }),
      CSVColumn("file size", { FileSizeFormatterUtil.string($0.fileSize) }),
      CSVColumn("resolution", { "\($0.width.map(String.init) ?? "?")x\($0.height.map(String.init) ?? "?")" }),
      CSVColumn("frame rate", { $0.frameRate.map { String(format: "%.2f", $0) } ?? "" }),
      CSVColumn("codec", { $0.codec ?? "" }),
      CSVColumn("shot time", { $0.effectiveShotTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) } ?? "" }),
      CSVColumn("shot time source", { $0.manualShotTime == nil ? $0.shotTimeSource.label : ShotTimeSource.manual.label })
    ]
    let production: [CSVColumn] = [
      CSVColumn("tags", { $0.productionTags.joined(separator: "; ") }),
      CSVColumn("people", { $0.people.joined(separator: "; ") }),
      CSVColumn("location", { $0.location }),
      CSVColumn("scene", { $0.scene }),
      CSVColumn("shot type", { $0.shotType }),
      CSVColumn("notes", { $0.customNotes }),
      CSVColumn("automatic tags", { $0.automaticTags.joined(separator: "; ") })
    ]
    let analysis: [CSVColumn] = [
      CSVColumn("analysis status", { $0.analysisStatus.label }),
      CSVColumn("quality score", { score($0.analysisQualityScore) }),
      CSVColumn("suggested rating", { $0.suggestedRating.map(String.init) ?? "" }),
      CSVColumn("focus score", { score($0.focusScore) }),
      CSVColumn("stability score", { score($0.stabilityScore) }),
      CSVColumn("brightness", { score($0.brightnessScore) }),
      CSVColumn("contrast", { score($0.contrastScore) }),
      CSVColumn("white balance estimate", { $0.whiteBalanceKelvin.map { "\($0)K" } ?? "" }),
      CSVColumn("face count", { $0.maxFaceCount.map(String.init) ?? "" }),
      CSVColumn("face visibility", { score($0.faceVisibilityScore) })
    ]
    let paths: [CSVColumn] = [
      CSVColumn("source path", { $0.originalSourcePath }),
      CSVColumn("destination path", { $0.currentPath })
    ]
    let status: [CSVColumn] = [
      CSVColumn("verification status", { $0.verificationStatus.rawValue }),
      CSVColumn("thumbnail status", { $0.thumbnailStatus.rawValue })
    ]
    switch kind {
    case .verification:
      return identity + [
        CSVColumn("expected size", { FileSizeFormatterUtil.string($0.expectedFileSize) }),
        CSVColumn("copied size", { FileSizeFormatterUtil.string($0.fileSize) }),
        CSVColumn("checksum", { $0.checksum ?? "" }),
        CSVColumn("copy status", { $0.copyStatus.rawValue }),
        CSVColumn("verification status", { $0.verificationStatus.rawValue }),
        CSVColumn("error", { $0.errorMessage ?? "" })
      ] + paths
    case .analysis:
      return identity + cull + analysis + [CSVColumn("sampled frames", { $0.sampledFrameCount.map(String.init) ?? "" })]
    case .allClips, .keeps, .rejects:
      return identity + cull + technical + production + analysis + paths + status
    }
  }

  private func escapeCSV(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
