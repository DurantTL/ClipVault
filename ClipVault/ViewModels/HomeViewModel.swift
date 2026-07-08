import Foundation
import AppKit

@MainActor final class HomeViewModel: ObservableObject {
    @Published var recentProjects: [String] = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
    func pickProject() -> ClipVaultProject? { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowedContentTypes = [.json]; return p.runModal() == .OK ? try? ProjectStore().load(from: p.url!) : nil }
}
