import Foundation

final class SecurityScopedBookmarkManager {
  struct ResolvedBookmark {
    var url: URL
    var isStale: Bool
  }

  /// A resolved bookmark plus, when the stored bookmark was stale (for example
  /// after its host server or volume was renamed), freshly minted replacement
  /// data. Callers should persist `refreshedData` when it is non-nil so the
  /// location keeps resolving on future launches instead of degrading further.
  struct HealedBookmark {
    var url: URL
    var refreshedData: Data?
  }

  func bookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  /// Resolves a security-scoped bookmark and, when macOS reports it stale,
  /// re-creates it from the resolved location so a renamed server or volume
  /// heals itself. `refreshedData` is non-nil only when new data was minted and
  /// should replace the stored bookmark.
  ///
  /// Returns `nil` when the bookmark cannot be resolved at all (the volume is
  /// unavailable or its identity changed beyond recognition); callers then fall
  /// back to any stored path or prompt the user to re-select the folder.
  func resolveHealing(_ data: Data, mountIfNeeded: Bool = true) -> HealedBookmark? {
    guard let resolved = try? resolveWithStaleness(data, mountIfNeeded: mountIfNeeded) else {
      return nil
    }
    guard resolved.isStale else {
      return HealedBookmark(url: resolved.url, refreshedData: nil)
    }
    // Creating a security-scoped bookmark requires the scope to be active in the
    // sandbox; minting it before starting access fails and `try?` would silently
    // drop the refreshed data, leaving the bookmark stale across launches.
    let refreshed = withAccess(to: resolved.url) { try? bookmark(for: resolved.url) }
    return HealedBookmark(url: resolved.url, refreshedData: refreshed)
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
