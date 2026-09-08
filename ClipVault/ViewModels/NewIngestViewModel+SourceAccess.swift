import AppKit
import Foundation

extension NewIngestViewModel {
  func chooseSource(settings: AppSettings) {
    if let url = pickFolder(canCreateDirectories: false) {
      var manual = volumeSourceService.manualSource(for: url)
      manual.bookmarkData = try? bookmarks.bookmark(for: url)
      if let bookmarkData = manual.bookmarkData { remember(bookmarkData, for: manual.id) }
      rememberManualSource(manual.url)
      if !recentManualSources.contains(where: { $0.id == manual.id }) {
        recentManualSources.insert(manual, at: 0)
      }
      let grant = SourceAccessGrant(url: url, needsBookmarkRefresh: manual.bookmarkData == nil)
      selectGrantedSource(manual, grant: grant, settings: settings)
    }
  }

  func refreshSources() {
    let selectedPath = sourceURL?.standardizedFileURL.path
    sourceOptions = volumeSourceService.scanMountedSources().map { option in
      var refreshed = option
      refreshed.bookmarkData = sourceBookmarkDataByID[option.id]
      return refreshed
    }
    recentManualSources = recentManualSources.map { manual in
      var refreshed = volumeSourceService.manualSource(for: manual.url)
      refreshed.isAvailable = FileManager.default.fileExists(atPath: manual.url.path)
      refreshed.bookmarkData = manual.bookmarkData ?? sourceBookmarkDataByID[manual.id]
      return refreshed
    }
    if let selectedPath, !sourceOptions.contains(where: { $0.id == selectedPath }) && !recentManualSources.contains(where: { $0.id == selectedPath }) {
      var disconnected = volumeSourceService.manualSource(for: URL(fileURLWithPath: selectedPath))
      disconnected.isAvailable = false
      recentManualSources.insert(disconnected, at: 0)
      selectedSourceID = selectedPath
    }
  }

  func selectDetectedSource(_ source: SourceVolumeOption, settings: AppSettings) {
    guard source.isAvailable else {
      error = "That source is disconnected. Reconnect it or use Add Source to choose a folder manually."
      return
    }
    guard let grant = ensureAccessForDetectedSource(source) else {
      error = "Access not granted. Choose the card or folder before \(AppBrand.appName) scans it."
      return
    }
    var grantedSource = volumeSourceService.manualSource(for: grant.url)
    grantedSource.id = source.id
    grantedSource.name = source.name
    grantedSource.volumeKind = source.volumeKind
    grantedSource.iconName = source.iconName
    grantedSource.bookmarkData = sourceBookmarkDataByID[source.id]
    selectGrantedSource(grantedSource, grant: grant, settings: settings)
  }

  private func selectGrantedSource(_ source: SourceVolumeOption, grant: SourceAccessGrant, settings: AppSettings) {
    retainAccess(to: grant.url)
    grantedSourceURLsByID[source.id] = grant.url
    // Refresh the persisted bookmark only while its security scope is active;
    // creating a security-scoped bookmark from a resolved URL fails before
    // access starts, which used to silently drop the refreshed bookmark.
    if grant.needsBookmarkRefresh || sourceBookmarkDataByID[source.id] == nil {
      if let refreshed = try? bookmarks.bookmark(for: grant.url) {
        remember(refreshed, for: source.id)
      }
    }
    sourceURL = grant.url
    selectedSourceID = source.id
    error = nil
    detectSonyCard()
    scan(settings: settings)
  }

  private func ensureAccessForDetectedSource(_ option: SourceVolumeOption) -> SourceAccessGrant? {
    // A source granted earlier in this app session stays granted. Swapping
    // between cards or drives in the ingest window must never prompt again
    // for a source the user already allowed.
    if let granted = grantedSourceURLsByID[option.id],
      FileManager.default.fileExists(atPath: granted.path) {
      return SourceAccessGrant(url: granted, needsBookmarkRefresh: false)
    }

    // Only volumes that macOS itself identifies as removable can use the
    // removable-media sandbox entitlement. Some card readers report an SD card
    // as a fixed external USB volume even when ClipVault recognizes its camera
    // layout; those need the normal one-time source picker below.
    if option.isRemovable {
      // Still remember a bookmark when possible so the same card keeps working
      // if a reader later mounts it as a fixed volume.
      return SourceAccessGrant(
        url: option.url, needsBookmarkRefresh: sourceBookmarkDataByID[option.id] == nil)
    }

    if let bookmarkData = option.bookmarkData ?? sourceBookmarkDataByID[option.id],
      let resolved = try? bookmarks.resolveWithStaleness(bookmarkData) {
      let resolvedPath = resolved.url.standardizedFileURL.path
      let optionPath = option.url.standardizedFileURL.path
      let coversOption = resolvedPath == optionPath || resolvedPath.hasPrefix(optionPath + "/")
      if coversOption && FileManager.default.fileExists(atPath: resolved.url.path) {
        return SourceAccessGrant(url: resolved.url, needsBookmarkRefresh: resolved.isStale)
      }
      // The bookmark points somewhere that no longer matches this mounted
      // volume (for example the card remounted under a new path), so fall
      // through and let the user grant the new location once.
    }

    let panel = NSOpenPanel()
    panel.title = "Allow \(AppBrand.appName) to Access This Source"
    panel.message = "Choose this card or folder so \(AppBrand.appName) can scan it."
    panel.prompt = "Allow Access"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    if FileManager.default.fileExists(atPath: option.url.path) {
      panel.directoryURL = option.url
    }

    guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
    let selectedPath = selectedURL.standardizedFileURL.path
    let detectedPath = option.url.standardizedFileURL.path
    guard selectedPath == detectedPath || selectedPath.hasPrefix(detectedPath + "/") else {
      error = "Choose the detected card or one of its folders to allow access."
      return nil
    }
    return SourceAccessGrant(url: selectedURL, needsBookmarkRefresh: true)
  }

  private func remember(_ bookmarkData: Data, for sourceID: String) {
    sourceBookmarkDataByID[sourceID] = bookmarkData
    if let data = try? PropertyListEncoder().encode(sourceBookmarkDataByID) {
      UserDefaults.standard.set(data, forKey: Self.rememberedSourceBookmarksKey)
    }
  }

  static func loadRememberedSourceBookmarks() -> [String: Data] {
    if let data = UserDefaults.standard.data(forKey: rememberedSourceBookmarksKey),
      let bookmarks = try? PropertyListDecoder().decode([String: Data].self, from: data) {
      return bookmarks
    }
    // Preserve permissions granted by the previous implementation when possible.
    return UserDefaults.standard.dictionary(forKey: rememberedSourceBookmarksKey) as? [String: Data] ?? [:]
  }

  private func rememberManualSource(_ url: URL) {
    let path = url.standardizedFileURL.path
    var paths = Self.loadRememberedManualSourcePaths()
    paths.removeAll { $0 == path }
    paths.insert(path, at: 0)
    UserDefaults.standard.set(Array(paths.prefix(20)), forKey: Self.rememberedManualSourcePathsKey)
  }

  static func loadRememberedManualSourcePaths() -> [String] {
    UserDefaults.standard.stringArray(forKey: rememberedManualSourcePathsKey) ?? []
  }

  func retainAccess(to url: URL) {
    let path = url.standardizedFileURL.path
    guard activeAccessURLsByPath[path] == nil else { return }
    // Keep security scope active for every source granted in this session so
    // swapping between cards never drops an earlier grant. Panel-granted URLs
    // and entitlement-covered removable volumes return false here; they are
    // accessible without explicit scope activation.
    if url.startAccessingSecurityScopedResource() {
      activeAccessURLsByPath[path] = url
    }
  }
}
