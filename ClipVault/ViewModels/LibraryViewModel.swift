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

/// Shell ViewModel for the Library. Focused work lives in collaborators:
/// selection, filter/sort, thumbnails, analysis, and export.
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
  @Published var operationError: String?
  @Published private(set) var canRetryProjectSave = false
  @Published private(set) var isResumingIngest = false

  let store = ProjectStore()
  let mover = FileMoveService()
  let security: SecurityScopedBookmarkManager
  let ingestService = IngestService()
  var accessedSecurityScopedURLs: [URL] = []

  let selectionController = LibrarySelectionController()
  let filterSort = LibraryFilterSortController()
  let thumbnailCoordinator: LibraryThumbnailCoordinator
  let analysisCoordinator = LibraryAnalysisCoordinator()
  let exportCoordinator: LibraryExportCoordinator

  /// Back-compat for callers that still read `analysis` (automatic tags / local analysis service).
  var analysis: LocalAnalysisService { analysisCoordinator.analysis }

  init(project: ClipVaultProject) {
    let securityManager = SecurityScopedBookmarkManager()
    self.security = securityManager
    self.thumbnailCoordinator = LibraryThumbnailCoordinator(security: securityManager)
    self.exportCoordinator = LibraryExportCoordinator(security: securityManager)
    self.project = project
    self.project.lastOpenedAt = Date()
    self.selectedClipID = project.clips.first(where: { $0.copyStatus == .copied || $0.verificationStatus == .verified })?.id ?? project.clips.first?.id
    self.selectedClipIDs = Set(project.clips.prefix(1).map(\.id))
    restoreSecurityScopedAccess()
    analysisCoordinator.applyAutomaticTags(project: &self.project)
    thumbnailCoordinator.normalizeExistingThumbnailPaths(project: &self.project)
    save()
    let backupWarningCount = self.project.clips.filter {
      $0.errorMessage?.hasPrefix("Primary verified. Backup warning:") == true
    }.count
    if backupWarningCount > 0 {
      operationError = "The primary ingest completed, but \(backupWarningCount) clip\(backupWarningCount == 1 ? "" : "s") has a backup warning. Use Needs Review to inspect the affected clips."
      canRetryProjectSave = false
    }
  }

  var selectedClip: Clip? { project.clips.first { $0.id == selectedClipID } }

  var productionTags: [String] {
    Array(Set(project.defaultTags + project.clips.flatMap { $0.productionTags + $0.automaticTags })).sorted()
  }

  var smartFolders: [String] { filterSort.smartFolders }

  var filteredClips: [Clip] {
    filterSort.filteredClips(
      from: project,
      filter: filter,
      sortOption: sortOption,
      ascending: sortAscending
    )
  }

  /// The sidebar keeps workflow filters intentionally small. Everything more
  /// specific is a tag or a project folder, which keeps the library readable
  /// as analysis and metadata grow.
  func clipCount(for filter: String) -> Int {
    filterSort.clipCount(in: project, filter: filter)
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

  func applySuggestedRatingsToUnrated() {
    analysisCoordinator.applySuggestedRatingsToUnrated(project: &project)
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
    selectionController.select(
      clip,
      extending: extending,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func selectRange(to clip: Clip) {
    selectionController.selectRange(
      to: clip,
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func selectAllVisible() {
    selectionController.selectAllVisible(
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func clearMultiSelection() {
    selectionController.clearMultiSelection(
      selectedClipID: selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func selectNext() {
    selectionController.select(
      offset: 1,
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func selectPrevious() {
    selectionController.select(
      offset: -1,
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func save() {
    do {
      try store.save(project)
      if canRetryProjectSave {
        operationError = nil
        canRetryProjectSave = false
      }
    } catch {
      operationError = StorageRecovery.message(for: error, operation: .projectSave)
      canRetryProjectSave = true
    }
  }

  func retryProjectSave() { save() }

  func dismissOperationError() {
    guard !canRetryProjectSave else { return }
    operationError = nil
  }

  func queueThumbnailGeneration(for ids: [UUID], force: Bool) {
    thumbnailCoordinator.enqueue(
      ids: ids,
      force: force,
      project: project,
      resolvedMediaURL: { [weak self] clip in self?.resolvedMediaURL(for: clip) }
    )
    thumbnailCoordinator.startProcessingIfNeeded(
      project: { [weak self] in self?.project ?? ClipVaultProject(name: "", projectFolderPath: "") },
      resolvedMediaURL: { [weak self] clip in self?.resolvedMediaURL(for: clip) },
      filteredClipIDs: { [weak self] in self?.filteredClips.map(\.id) ?? [] },
      selectedClipID: { [weak self] in self?.selectedClipID },
      mutate: { [weak self] id, edit in
        guard let self, let index = self.project.clips.firstIndex(where: { $0.id == id }) else { return }
        edit(&self.project.clips[index])
      },
      save: { [weak self] in self?.save() }
    )
  }

  var activeSelectionIDs: Set<UUID> {
    selectionController.activeSelectionIDs(selectedClipID: selectedClipID, selectedClipIDs: selectedClipIDs)
  }

  func advanceAfterRating() {
    selectionController.advanceAfterRating(
      previous: AppSettings.advanceDirectionPrevious,
      filteredClips: filteredClips,
      selectedClipID: &selectedClipID,
      selectedClipIDs: &selectedClipIDs
    )
  }

  func mediaURLCandidates(for clip: Clip, in project: ClipVaultProject) -> [URL] {
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

  func restoreSecurityScopedAccess() {
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
    thumbnailCoordinator.cancel()
    analysisCoordinator.cancel()
    for url in accessedSecurityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
