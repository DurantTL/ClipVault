import AppKit
import Foundation

@MainActor final class HomeViewModel: ObservableObject {
  @Published var recentProjects: [String] =
    UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
  @Published var error: String?
  func pickProject() -> ClipVaultProject? {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = true
    p.allowsMultipleSelection = false
    p.treatsFilePackagesAsDirectories = true
    p.message = "Select a ClipVault project folder or its hidden .clipvault-project.json file."
    guard p.runModal() == .OK, let url = p.url else { return nil }
    return loadProject(at: url)
  }
  func loadProject(at url: URL) -> ClipVaultProject? {
    do {
      let project = try ProjectStore().load(from: url)
      recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
      return project
    } catch {
      self.error =
        "Could not open this project. If it is on an external SSD or NAS, make sure the volume is connected and mounted. \(error.localizedDescription)"
      return nil
    }
  }
  func loadRecent(path: String) -> ClipVaultProject? {
    do {
      let project = try ProjectStore().loadRecent(path: path)
      recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
      return project
    } catch {
      self.error =
        "Could not open this recent project. If it is on an external SSD or NAS, make sure the volume is connected and mounted. \(error.localizedDescription)"
      return nil
    }
  }
}
