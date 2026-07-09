import Foundation

final class SecurityScopedBookmarkManager {
  struct ResolvedBookmark {
    var url: URL
    var isStale: Bool
  }

  func bookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
  }
  func resolve(_ data: Data) throws -> URL {
    try resolveWithStaleness(data).url
  }
  func resolveWithStaleness(_ data: Data) throws -> ResolvedBookmark {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    return ResolvedBookmark(url: url, isStale: stale)
  }
  func withAccess<T>(to url: URL, _ work: () throws -> T) rethrows -> T {
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    return try work()
  }
  func withAccessAsync<T>(to url: URL, _ work: () async throws -> T) async rethrows -> T {
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    return try await work()
  }
  func projectFolderURL(for project: ClipVaultProject) -> URL {
    if let data = project.projectFolderBookmarkData, let resolved = try? resolve(data) {
      return resolved
    }
    return URL(fileURLWithPath: project.projectFolderPath)
  }
}
