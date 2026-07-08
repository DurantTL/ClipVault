import AppKit
import Foundation

@MainActor final class LibraryViewModel: ObservableObject {
  @Published var project: ClipVaultProject
  @Published var selectedClipID: UUID?
  @Published var filter: String = "All Clips"
  @Published var previewClip: Clip?
  @Published var thumbnailSize: Double = 190

  let store = ProjectStore()
  let mover = FileMoveService()
  let security = SecurityScopedBookmarkManager()

  init(project: ClipVaultProject) {
    self.project = project
    self.project.lastOpenedAt = Date()
    self.selectedClipID = project.clips.first?.id
    save()
  }

  var selectedClip: Clip? { project.clips.first { $0.id == selectedClipID } }

  var productionTags: [String] {
    Array(Set(project.defaultTags + project.clips.flatMap { $0.productionTags + $0.automaticTags })).sorted()
  }

  var filteredClips: [Clip] {
    project.clips.filter { clip in
      filter == "All Clips" || filter.lowercased() == clip.cullStatus.rawValue
        || clip.assignedFolder == filter || clip.productionTags.contains(filter)
        || clip.automaticTags.contains(filter)
    }
  }

  func setStatus(_ status: CullStatus) {
    updateSelected { $0.cullStatus = status }
  }

  func updateSelected(_ edit: (inout Clip) -> Void) {
    guard let id = selectedClipID, let index = project.clips.firstIndex(where: { $0.id == id }) else {
      return
    }
    edit(&project.clips[index])
    save()
  }

  func selectNext() { select(offset: 1) }
  func selectPrevious() { select(offset: -1) }

  private func select(offset: Int) {
    let clips = filteredClips
    guard !clips.isEmpty else { return }
    let current = selectedClipID.flatMap { id in clips.firstIndex { $0.id == id } } ?? 0
    selectedClipID = clips[min(max(current + offset, 0), clips.count - 1)].id
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

  func moveSelected(to folder: String) {
    guard let id = selectedClipID, let i = project.clips.firstIndex(where: { $0.id == id }) else {
      return
    }
    do {
      try mover.move(
        clip: &project.clips[i], to: folder, projectFolder: security.projectFolderURL(for: project))
      save()
    } catch { project.clips[i].errorMessage = error.localizedDescription }
  }

  func undoMove() {
    do {
      try mover.undo(project: &project)
      save()
    } catch {}
  }

  func reveal() {
    if let clip = selectedClip {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: clip.currentPath)])
    }
  }

  func revealProject() {
    NSWorkspace.shared.activateFileViewerSelecting([security.projectFolderURL(for: project)])
  }

  func save() { try? store.save(project) }
}
