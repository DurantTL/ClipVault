import AppKit
import Foundation

@MainActor final class NewIngestViewModel: ObservableObject {
  @Published var sourceURL: URL?
  @Published var destinationURL: URL?
  @Published var projectName = ""
  @Published var videos: [SourceVideo] = []
  @Published var progress = IngestProgress()
  @Published var error: String?
  @Published var isIngesting = false
  let scanner = SourceScanner()
  let bookmarks = SecurityScopedBookmarkManager()
  let ingestService = IngestService()
  init() {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    projectName = "\(f.string(from: Date())) Video Ingest"
  }
  func chooseSource(settings: AppSettings) {
    if let u = pickFolder() {
      sourceURL = u
      scan(settings: settings)
    }
  }
  func chooseDestination() { destinationURL = pickFolder() }
  func pickFolder() -> URL? {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.allowsMultipleSelection = false
    return p.runModal() == .OK ? p.url : nil
  }
  func scan(settings: AppSettings) {
    guard let sourceURL else { return }
    do {
      videos = try scanner.scan(source: sourceURL, includeProxyFiles: settings.includeProxyFiles)
    } catch { self.error = error.localizedDescription }
  }
  func start(settings: AppSettings) async -> ClipVaultProject? {
    guard let s = sourceURL, let d = destinationURL else { return nil }
    isIngesting = true
    defer { isIngesting = false }
    do {
      return try await ingestService.ingest(
        name: projectName, source: s, destination: d, videos: videos,
        bookmarks: (try? bookmarks.bookmark(for: s), try? bookmarks.bookmark(for: d)),
        settings: settings
      ) { self.progress = $0 }
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }
}
