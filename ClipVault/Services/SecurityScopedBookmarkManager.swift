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
  /// Resolves a security-scoped bookmark.
  ///
  /// Pass `mountIfNeeded: false` on launch/display paths so a bookmark that
  /// points at a disconnected network drive or external volume fails fast
  /// instead of blocking the calling thread while macOS tries to mount it.
  func resolve(_ data: Data, mountIfNeeded: Bool = true) throws -> URL {
    try resolveWithStaleness(data, mountIfNeeded: mountIfNeeded).url
  }
  func resolveWithStaleness(_ data: Data, mountIfNeeded: Bool = true) throws -> ResolvedBookmark {
    var stale = false
    var options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
    if !mountIfNeeded { options.insert(.withoutMounting) }
    let url = try URL(
      resolvingBookmarkData: data, options: options, relativeTo: nil,
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
