import AppKit
import Foundation

struct RecentProjectSummary: Identifiable {
  let id = UUID()
  let path: String
  let project: ClipVaultProject?

  var name: String { project?.name ?? URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent }
  var coverThumbnail: String? { project?.clips.first(where: { $0.thumbnailPath != nil })?.thumbnailPath }
  var projectFolderPath: String? { project?.projectFolderPath ?? URL(fileURLWithPath: path).deletingLastPathComponent().path }
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
  @Published var recentProjects: [String]
  @Published private(set) var summaries: [RecentProjectSummary]
  @Published var error: String?

  init() {
    let paths = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
    recentProjects = paths
    summaries = Self.loadSummaries(for: paths)
  }

  /// Builds the recent-project summaries. Bookmarks are resolved without
  /// mounting so a project on a disconnected network drive is shown as
  /// unavailable instead of stalling the Home screen while macOS tries to
  /// mount the volume.
  private static func loadSummaries(for paths: [String]) -> [RecentProjectSummary] {
    paths.map { path in
      RecentProjectSummary(path: path, project: try? ProjectStore().loadRecent(path: path, mountIfNeeded: false))
    }
  }

  /// Recomputes the cached summaries. Call after the recent-project list changes.
  func refreshSummaries() {
    summaries = Self.loadSummaries(for: recentProjects)
  }

  func pickProject() -> ClipVaultProject? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = true
    panel.message = "Select a \(AppBrand.appName) project folder or its hidden \(AppBrand.metadataFileName) file."
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return loadProject(at: url)
  }

  func loadProject(at url: URL) -> ClipVaultProject? {
    do {
      let project = try ProjectStore().load(from: url)
      recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
      refreshSummaries()
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
      refreshSummaries()
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
    refreshSummaries()
  }
}
