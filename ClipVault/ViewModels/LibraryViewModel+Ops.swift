import AppKit
import Foundation

extension LibraryViewModel {
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
    } catch {
      operationError = "The last move could not be undone: \(error.localizedDescription)"
      canRetryProjectSave = false
    }
  }

  func reveal() {
    let urls = activeSelectionIDs.compactMap { id -> URL? in
      guard let clip = project.clips.first(where: { $0.id == id }) else { return nil }
      return resolvedMediaURL(for: clip)
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [security.projectFolderURL(for: project)] : urls)
  }

  func resumeIngest() {
    guard !isResumingIngest else { return }
    Task {
      isResumingIngest = true
      operationError = nil
      canRetryProjectSave = false
      defer { isResumingIngest = false }
      do {
        project = try await ingestService.resume(
          project: project,
          settings: AppSettings()
        ) { _ in }
        if project.failedClipCount > 0 {
          operationError = "Resume finished with \(project.failedClipCount) clip\(project.failedClipCount == 1 ? "" : "s") still needing attention. Reconnect missing storage, then retry the ingest."
        }
      } catch {
        let message = StorageRecovery.message(for: error, operation: .resumeIngest)
        for index in project.clips.indices where project.clips[index].verificationStatus != .verified {
          project.clips[index].errorMessage = message
        }
        project.ingestStatus = .incomplete
        project.ingestIncomplete = true
        project.canResumeIngest = true
        save()
        if !canRetryProjectSave {
          operationError = message
          canRetryProjectSave = false
        }
      }
    }
  }

  func revealProject() {
    NSWorkspace.shared.activateFileViewerSelecting([security.projectFolderURL(for: project)])
  }

  func copySelectedFilenames() {
    let names = activeSelectionIDs.compactMap { id in project.clips.first { $0.id == id }?.currentFilename }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
  }

}
