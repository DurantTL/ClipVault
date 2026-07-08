import AppKit
import Foundation

struct RecentProjectSummary: Identifiable {
  let id = UUID()
  let path: String
  let project: ClipVaultProject?

  var name: String { project?.name ?? URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent }
  var coverThumbnail: String? { project?.clips.first(where: { $0.thumbnailPath != nil })?.thumbnailPath }
  var createdAt: Date? { project?.createdAt }
  var lastOpenedAt: Date? { project?.lastOpenedAt }
  var clipCount: Int { project?.clips.count ?? 0 }
  var totalSize: Int64 { project?.clips.reduce(0) { $0 + $1.fileSize } ?? 0 }
  var kept: Int { project?.clips.filter { $0.cullStatus == .keep }.count ?? 0 }
  var maybe: Int { project?.clips.filter { $0.cullStatus == .maybe }.count ?? 0 }
  var rejected: Int { project?.clips.filter { $0.cullStatus == .reject }.count ?? 0 }
  var statusLabel: String { project?.ingestStatus.label ?? "Unavailable" }
  var isPartial: Bool { project.map { $0.ingestStatus != .complete } ?? false }
}

@MainActor final class HomeViewModel: ObservableObject {
  @Published var recentProjects: [String] = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
  @Published var error: String?

  var summaries: [RecentProjectSummary] {
    recentProjects.map { RecentProjectSummary(path: $0, project: try? ProjectStore().loadRecent(path: $0)) }
  }

  func pickProject() -> ClipVaultProject? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = true
    panel.message = "Select a ClipVault project folder or its hidden .clipvault-project.json file."
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return loadProject(at: url)
  }

  func loadProject(at url: URL) -> ClipVaultProject? {
    do {
      let project = try ProjectStore().load(from: url)
      recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
      return project
    } catch {
      self.error = "Could not open this project. Make sure the volume is connected. \(error.localizedDescription)"
      return nil
    }
  }

  func loadRecent(path: String) -> ClipVaultProject? {
    do {
      let project = try ProjectStore().loadRecent(path: path)
      recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
      return project
    } catch {
      self.error = "Could not open this recent project. Make sure the volume is connected. \(error.localizedDescription)"
      return nil
    }
  }

  func reveal(path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }

  func removeRecent(path: String) {
    recentProjects.removeAll { $0 == path }
    UserDefaults.standard.set(recentProjects, forKey: "recentProjects")
  }
}
