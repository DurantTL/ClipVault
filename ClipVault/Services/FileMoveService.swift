import Foundation

struct MoveRecord { let clipID: UUID; let from: URL; let to: URL; let oldFolder: String? }
final class FileMoveService {
    var lastMove: MoveRecord?
    private let security = SecurityScopedBookmarkManager()
    func move(clip: inout Clip, to folder: String, projectFolder: URL) throws {
        try security.withAccess(to: projectFolder) {
            let targetDir = projectFolder.appendingPathComponent(SafeFilename.safeFolderName(folder), isDirectory: true); try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let from = URL(fileURLWithPath: clip.currentPath); let to = SafeFilename.uniqueURL(for: targetDir.appendingPathComponent(clip.currentFilename))
            try FileManager.default.moveItem(at: from, to: to); lastMove = MoveRecord(clipID: clip.id, from: from, to: to, oldFolder: clip.assignedFolder)
            clip.currentPath = to.path; clip.currentFilename = to.lastPathComponent; clip.assignedFolder = folder; clip.relativePath = to.path.replacingOccurrences(of: projectFolder.path + "/", with: "")
        }
    }
    func undo(project: inout ClipVaultProject) throws {
        let projectFolder = security.projectFolderURL(for: project)
        try security.withAccess(to: projectFolder) {
            guard let m = lastMove, let i = project.clips.firstIndex(where: {$0.id == m.clipID}) else { return }
            let dest = SafeFilename.uniqueURL(for: m.from); try FileManager.default.moveItem(at: m.to, to: dest)
            project.clips[i].currentPath = dest.path; project.clips[i].currentFilename = dest.lastPathComponent; project.clips[i].assignedFolder = m.oldFolder; project.clips[i].relativePath = dest.path.replacingOccurrences(of: projectFolder.path + "/", with: "")
            lastMove = nil
        }
    }
}
