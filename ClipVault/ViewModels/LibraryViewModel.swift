import Foundation
import AppKit

@MainActor final class LibraryViewModel: ObservableObject {
    @Published var project: ClipVaultProject; @Published var selectedClipID: UUID?; @Published var filter: String = "All Clips"; @Published var previewClip: Clip?; let store = ProjectStore(); let mover = FileMoveService()
    init(project: ClipVaultProject) { self.project = project; self.selectedClipID = project.clips.first?.id }
    var selectedClip: Clip? { project.clips.first { $0.id == selectedClipID } }
    var filteredClips: [Clip] { project.clips.filter { c in filter == "All Clips" || filter.lowercased() == c.cullStatus.rawValue || c.assignedFolder == filter } }
    func setStatus(_ s: CullStatus) { guard let id = selectedClipID, let i = project.clips.firstIndex(where: {$0.id == id}) else { return }; project.clips[i].cullStatus = s; save() }
    func addFolder(_ name: String) { let f = SafeFilename.safeFolderName(name); if !f.isEmpty && !project.customFolders.contains(f) { project.customFolders.append(f); save() } }
    func moveSelected(to folder: String) { guard let id = selectedClipID, let i = project.clips.firstIndex(where: {$0.id == id}) else { return }; do { try mover.move(clip: &project.clips[i], to: folder, projectFolder: URL(fileURLWithPath: project.projectFolderPath)); save() } catch { project.clips[i].errorMessage = error.localizedDescription } }
    func undoMove() { do { try mover.undo(project: &project); save() } catch {} }
    func reveal() { if let c = selectedClip { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.currentPath)]) } }
    func save() { try? store.save(project) }
}
