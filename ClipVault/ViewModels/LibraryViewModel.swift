import AppKit
import Foundation

enum ClipSortOption: String, CaseIterable, Identifiable {
  case ingestOrder = "Ingest Order"
  case filename = "Filename"
  case createdDate = "Created Date"
  case duration = "Duration"
  case fileSize = "File Size"
  case cullStatus = "Cull Status"

  var id: String { rawValue }
}

@MainActor final class LibraryViewModel: ObservableObject {
  @Published var project: ClipVaultProject
  @Published var selectedClipID: UUID?
  @Published var selectedClipIDs: Set<UUID> = []
  @Published var filter: String = "All Clips"
  @Published var sortOption: ClipSortOption = .ingestOrder
  @Published var previewClip: Clip?
  @Published var thumbnailSize: Double = 190

  let store = ProjectStore()
  let mover = FileMoveService()
  let security = SecurityScopedBookmarkManager()
  let analysis = LocalAnalysisService()

  init(project: ClipVaultProject) {
    self.project = project
    self.project.lastOpenedAt = Date()
    self.selectedClipID = project.clips.first?.id
    self.selectedClipIDs = Set(project.clips.prefix(1).map(\.id))
    applyAutomaticTags()
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
      "Low Contrast", "Failed Analysis"
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
    if let clip = selectedClip { previewClip = clip }
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
    let urls = activeSelectionIDs.compactMap { id in
      project.clips.first { $0.id == id }.map { URL(fileURLWithPath: $0.currentPath) }
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [security.projectFolderURL(for: project)] : urls)
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
    case "Possibly Out of Focus", "Faces", "Group Shots", "Close Faces", "Low Face Visibility", "Possibly Shaky", "Stable Clips", "High Motion", "Dark Clips", "Bright Clips", "Low Contrast", "Failed Analysis": return clip.automaticTags.contains(filter)
    case "Social Candidates": return clip.isSocialClipCandidate
    case "Interviews": return clip.isInterview
    case "B-Roll": return clip.isBroll || clip.assignedFolder == filter
    case "Sermon": return clip.isSermon || clip.assignedFolder == filter
    default:
      return clip.assignedFolder == filter || clip.productionTags.contains(filter) || clip.automaticTags.contains(filter)
    }
  }

  private func sorted(_ clips: [Clip]) -> [Clip] {
    switch sortOption {
    case .ingestOrder: return clips.sorted { ($0.ingestDate ?? .distantPast) < ($1.ingestDate ?? .distantPast) }
    case .filename: return clips.sorted { $0.currentFilename.localizedStandardCompare($1.currentFilename) == .orderedAscending }
    case .createdDate: return clips.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    case .duration: return clips.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
    case .fileSize: return clips.sorted { $0.fileSize < $1.fileSize }
    case .cullStatus: return clips.sorted { $0.cullStatus.rawValue < $1.cullStatus.rawValue }
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
